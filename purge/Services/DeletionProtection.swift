import Foundation
import LocalAuthentication

nonisolated struct ProtectedItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let path: String?
    let bookmark: Data?
    let dockerKey: String?

    var resolvedPaths: [String] {
        guard let path else { return [] }
        var paths = [URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path]
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                paths.append(url.standardizedFileURL.resolvingSymlinksInPath().path)
            }
        }
        return paths
    }
}

nonisolated struct ProtectionGrant: Sendable {
    fileprivate let ids: Set<UUID>
    fileprivate let expires: TimeInterval
    fileprivate func permits(_ items: [ProtectedItem]) -> Bool {
        ProcessInfo.processInfo.systemUptime < expires && items.allSatisfy { ids.contains($0.id) }
    }
}

nonisolated enum ProtectionError: LocalizedError {
    case unavailable, authentication, protectedItem
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Protection records could not be read or saved. Deletion is blocked until this is resolved."
        case .authentication: return "Deletion cancelled. Protected items require Touch ID or your Mac login password."
        case .protectedItem: return "This item is protected. Use Touch ID or your Mac login password before deleting it."
        }
    }
}

/// Thread-safe protection is enforced by the deletion engine, not just by row selection.
/// A corrupt/unwritable store fails closed. Tests never read the personal protection file.
nonisolated final class DeletionProtection: @unchecked Sendable {
    static let shared: DeletionProtection = {
        if TestHost.isActive() { return DeletionProtection(fileURL: nil) }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.getpurge.app/protected-items.json")
        return DeletionProtection(fileURL: url)
    }()
    private let lock = NSRecursiveLock()
    private let fileURL: URL?
    private var records: [ProtectedItem] = []
    private var unavailable = false

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL {
            do {
                let loaded = try JSONDecoder().decode([ProtectedItem].self, from: Data(contentsOf: fileURL))
                guard Set(loaded.map(\.id)).count == loaded.count,
                      loaded.allSatisfy({ item in
                          if let path = item.path { return path.hasPrefix("/") && item.dockerKey == nil }
                          return item.bookmark == nil && !(item.dockerKey ?? "").isEmpty
                      }) else { throw ProtectionError.unavailable }
                records = loaded
            }
            catch let error as NSError {
                // fileExists reports false on permission errors too. Only a genuine missing
                // file is an empty first-run store; unreadable/corrupt stores block deletion.
                if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileReadNoSuchFile.rawValue {
                    unavailable = true
                }
            }
        }
    }

    func snapshot() throws -> [ProtectedItem] {
        lock.lock(); defer { lock.unlock() }
        guard !unavailable else { throw ProtectionError.unavailable }
        return records
    }

    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs == "/" ? "/" : rhs + "/") || rhs.hasPrefix(lhs == "/" ? "/" : lhs + "/")
    }

    func matching(urls: [URL] = [], dockerKey: String? = nil, allFiles: Bool = false) throws -> [ProtectedItem] {
        let paths = urls.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        return try snapshot().filter { item in
            if let dockerKey, item.dockerKey == dockerKey { return true }
            if allFiles { return item.path != nil }
            return item.resolvedPaths.contains { root in paths.contains { Self.overlaps(root, $0) } }
        }
    }

    func allows(url: URL, grant: ProtectionGrant?) -> Bool {
        guard let matches = try? matching(urls: [url]) else { return false }
        return matches.isEmpty || grant?.permits(matches) == true
    }

    func allows(dockerKey: String, grant: ProtectionGrant?) -> Bool {
        guard let matches = try? matching(dockerKey: dockerKey) else { return false }
        return matches.isEmpty || grant?.permits(matches) == true
    }

    func allowsEmptyTrash(grant: ProtectionGrant?) -> Bool {
        guard let matches = try? matching(allFiles: true) else { return false }
        // Conservative: authenticate whenever any file lock exists, even if its bookmark went stale.
        return matches.isEmpty || grant?.permits(matches) == true
    }

    @discardableResult func protect(url: URL, name: String? = nil) throws -> ProtectedItem {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return try insert(ProtectedItem(id: UUID(), name: name ?? url.lastPathComponent,
                                       path: path, bookmark: bookmark, dockerKey: nil))
    }

    @discardableResult func protectDocker(key: String, name: String) throws -> ProtectedItem {
        try insert(ProtectedItem(id: UUID(), name: name, path: nil, bookmark: nil, dockerKey: key))
    }

    private func insert(_ item: ProtectedItem) throws -> ProtectedItem {
        lock.lock(); defer { lock.unlock() }
        guard !unavailable else { throw ProtectionError.unavailable }
        if let existing = records.first(where: { item.path != nil ? $0.path == item.path : $0.dockerKey == item.dockerKey }) {
            return existing
        }
        let updated = records + [item]
        try save(updated)
        records = updated
        return item
    }

    func remove(_ item: ProtectedItem, grant: ProtectionGrant) throws {
        lock.lock(); defer { lock.unlock() }
        guard !unavailable else { throw ProtectionError.unavailable }
        guard grant.permits([item]) else { throw ProtectionError.authentication }
        let updated = records.filter { $0.id != item.id }
        try save(updated)
        records = updated
    }

    private func save(_ values: [ProtectedItem]) throws {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            unavailable = true
            throw ProtectionError.unavailable
        }
    }
}

@MainActor enum ProtectionAuthentication {
    static func deviceOwner(reason: String) async -> Bool {
        guard !TestHost.isActive() else { return false }
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }

    static func authorize(
        store: DeletionProtection = .shared, urls: [URL] = [], dockerKey: String? = nil,
        allFiles: Bool = false, items: [ProtectedItem]? = nil, interactive: Bool = true,
        authenticate: ((String) async -> Bool)? = nil
    ) async throws -> ProtectionGrant? {
        let matches: [ProtectedItem]
        if let items { matches = items }
        else {
            matches = try await Task.detached(priority: .userInitiated) {
                try store.matching(urls: urls, dockerKey: dockerKey, allFiles: allFiles)
            }.value
        }
        guard !matches.isEmpty else { return nil }
        guard interactive else { return nil }
        let reason = "Allow this action for \(matches.count) protected item(s) in Purge. Protection stays enabled afterwards."
        let authenticated = if let authenticate { await authenticate(reason) } else { await deviceOwner(reason: reason) }
        guard authenticated else { throw ProtectionError.authentication }
        return ProtectionGrant(ids: Set(matches.map(\.id)), expires: ProcessInfo.processInfo.systemUptime + 300)
    }
}
