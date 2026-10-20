import Foundation

nonisolated enum DockerKind: String, CaseIterable, Codable, Hashable, Sendable {
    case image = "Images", container = "Containers", volume = "Volumes", buildCache = "Build cache"
}

nonisolated struct DockerResource: Identifiable, Hashable, Sendable {
    let kind: DockerKind
    let objectID: String
    let name: String
    let sizeBytes: Int64?
    let detail: String
    let canRemove: Bool
    var revision: String = ""
    var id: String { kind.rawValue + ":" + objectID }
    func protectionKey(daemonID: String) -> String {
        let parts = [daemonID, kind.rawValue, objectID]
        return "docker:" + (try! JSONEncoder().encode(parts)).base64EncodedString()
    }
}

nonisolated struct DockerSnapshot: Sendable {
    let daemonID: String
    let resources: [DockerResource]
}

nonisolated enum DockerError: LocalizedError {
    case offline, unsafeContext, changed, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .offline: return "Docker Desktop is offline or unavailable. Start it when you are ready, then refresh."
        case .unsafeContext: return "Purge only manages the local Docker Desktop context. Remote Docker endpoints are not allowed."
        case .changed: return "Docker changed since this review. Refresh and review the item again."
        case .unavailable(let message): return message
        }
    }
}

/// Uses a versioned Engine API over the local Docker Desktop socket, never a shell or remote host.
/// Deletion is individual, never forced, never a prune, and never includes container volumes.
nonisolated struct DockerClient: Sendable {
    static var dataRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.docker.docker")
    }
    typealias Request = @Sendable (_ method: String, _ path: String) async throws -> Data
    private let fixtureRequest: Request?
    private let protections: DeletionProtection
    init(protections: DeletionProtection = .shared, request: Request? = nil) {
        self.protections = protections
        fixtureRequest = request
    }

    static func acceptedSocket(_ endpoint: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let allowed = home.appendingPathComponent(".docker/run/docker.sock").standardizedFileURL.path
        guard endpoint == "unix://" + allowed else { return nil }
        return allowed
    }

    private func socket() async throws -> String {
        if fixtureRequest != nil { return "fixture" }
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
        guard let docker = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let result = await ProcessRunner.runAsync(executablePath: docker,
                arguments: ["context", "inspect", "desktop-linux", "--format", "{{json .Endpoints.docker.Host}}"], timeout: 8),
              result.succeeded,
              let endpoint = try? JSONDecoder().decode(String.self, from: result.stdout) else { throw DockerError.offline }
        guard let socket = Self.acceptedSocket(endpoint) else { throw DockerError.unsafeContext }
        return socket
    }

    private func request(_ method: String, _ path: String, socket: String) async throws -> Data {
        if let fixtureRequest { return try await fixtureRequest(method, path) }
        let arguments = ["--disable", "--proto", "=http", "--globoff", "--silent", "--show-error", "--fail-with-body", "--noproxy", "*",
                         "--max-time", "20", "--max-filesize", "16777216", "--unix-socket", socket,
                         "--request", method, "http://localhost/v1.47" + path]
        guard let result = await ProcessRunner.runAsync(executablePath: "/usr/bin/curl", arguments: arguments, timeout: 23),
              !result.timedOut, result.stdout.count <= 16_777_216 else { throw DockerError.offline }
        guard result.succeeded else {
            if let message = (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any],
               let text = message["message"] as? String {
                throw DockerError.unavailable(String(text.prefix(500)))
            }
            throw DockerError.offline
        }
        return result.stdout
    }

    @concurrent func load() async throws -> DockerSnapshot {
        let socket = try await socket()
        let info = try await request("GET", "/info", socket: socket)
        guard let object = try JSONSerialization.jsonObject(with: info) as? [String: Any],
              let daemonID = object["ID"] as? String, !daemonID.isEmpty else { throw DockerError.changed }
        let usage = try await request("GET", "/system/df", socket: socket)
        return DockerSnapshot(daemonID: daemonID, resources: try Self.parseUsage(usage))
    }

    static func parseUsage(_ data: Data) throws -> [DockerResource] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.contains("Images"), object.keys.contains("Containers"), object.keys.contains("Volumes") else {
            throw DockerError.unavailable("Docker returned an unsupported disk-usage response.")
        }
        func rows(_ key: String) -> [[String: Any]] { object[key] as? [[String: Any]] ?? [] }
        func number(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
        func size(_ value: Any?) -> Int64? { number(value).flatMap { $0 >= 0 ? $0 : nil } }
        func display(_ value: String) -> String {
            String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(160))
        }
        var resources: [DockerResource] = []
        for row in rows("Images") {
            guard let id = row["Id"] as? String ?? row["ID"] as? String else { continue }
            let tags = row["RepoTags"] as? [String] ?? []
            let count = number(row["Containers"])
            resources.append(DockerResource(kind: .image, objectID: id,
                name: display(tags.first ?? String(id.prefix(19))), sizeBytes: size(row["Size"]),
                detail: count == 0 ? "Unused image. Shared layers may be retained." : "Referenced by containers; removal disabled.",
                canRemove: count == 0 && validID(id, kind: .image)))
        }
        for row in rows("Containers") {
            guard let id = row["Id"] as? String ?? row["ID"] as? String else { continue }
            let state = row["State"] as? String ?? "unknown"
            let name = (row["Names"] as? [String])?.first ?? String(id.prefix(12))
            resources.append(DockerResource(kind: .container, objectID: id, name: display(name),
                sizeBytes: size(row["SizeRw"]), detail: "\(state.capitalized). Removal keeps its Docker volumes.",
                canRemove: ["exited", "created", "dead"].contains(state) && validID(id, kind: .container)))
        }
        for row in rows("Volumes") {
            guard let name = row["Name"] as? String else { continue }
            let usage = row["UsageData"] as? [String: Any] ?? [:]
            let references = number(usage["RefCount"])
            resources.append(DockerResource(kind: .volume, objectID: name, name: display(name), sizeBytes: size(usage["Size"]),
                detail: references == 0 ? "Unused. May contain irreplaceable database or application data." : "In use or usage unknown; removal disabled.",
                canRemove: references == 0 && validID(name, kind: .volume) && !(row["CreatedAt"] as? String ?? "").isEmpty,
                revision: row["CreatedAt"] as? String ?? ""))
        }
        for row in rows("BuildCache") {
            guard let id = row["ID"] as? String else { continue }
            resources.append(DockerResource(kind: .buildCache, objectID: id,
                name: display(row["Description"] as? String ?? id), sizeBytes: size(row["Size"]),
                detail: "Review only. Bulk pruning could delete protected cache records.", canRemove: false))
        }
        return resources.sorted { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
    }

    static func validID(_ id: String, kind: DockerKind) -> Bool {
        switch kind {
        case .image: return id.range(of: "^(sha256:)?[a-f0-9]{64}$", options: .regularExpression) != nil
        case .container: return id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        case .volume: return id.count <= 255 && id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.-]*$", options: .regularExpression) != nil
        case .buildCache: return false
        }
    }

    static func deletionPath(for item: DockerResource) throws -> String {
        guard item.canRemove, validID(item.objectID, kind: item.kind),
              let encoded = item.objectID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) else {
            throw DockerError.changed
        }
        switch item.kind {
        case .image: return "/images/\(encoded)?force=false&noprune=true"
        case .container: return "/containers/\(encoded)?force=false&v=false"
        case .volume: return "/volumes/\(encoded)?force=false"
        case .buildCache: throw DockerError.changed
        }
    }

    @concurrent func remove(_ item: DockerResource, daemonID: String, grant: ProtectionGrant?) async throws {
        let socket = try await socket()
        let current = try await load()
        guard current.daemonID == daemonID,
              let fresh = current.resources.first(where: { $0.id == item.id }), fresh.canRemove,
              fresh.revision == item.revision else { throw DockerError.changed }
        // Check daemon again on the exact socket used for mutation, not a changed context.
        let info = try await request("GET", "/info", socket: socket)
        let object = try JSONSerialization.jsonObject(with: info) as? [String: Any]
        guard object?["ID"] as? String == daemonID else { throw DockerError.changed }
        guard protections.allows(dockerKey: fresh.protectionKey(daemonID: daemonID), grant: grant),
              protections.allows(url: Self.dataRoot, grant: grant) else { throw ProtectionError.protectedItem }
        _ = try await request("DELETE", Self.deletionPath(for: fresh), socket: socket)
    }
}
