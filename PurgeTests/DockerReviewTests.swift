import Foundation
import Testing
@testable import Purge

private actor DockerFixture {
    var requests: [String] = []
    let usage: Data
    let daemon: String
    init(usage: Data, daemon: String = "local-fixture") { self.usage = usage; self.daemon = daemon }
    func request(_ method: String, _ path: String) throws -> Data {
        requests.append(method + " " + path)
        if path == "/info" { return try JSONSerialization.data(withJSONObject: ["ID": daemon]) }
        if path == "/system/df" { return usage }
        if method == "DELETE" { return Data("[]".utf8) }
        throw DockerError.changed
    }
}

@Suite("Docker review and protected removals")
struct DockerReviewTests {
    private let imageID = "sha256:" + String(repeating: "a", count: 64)
    private func usage(created: String = "2026-10-19T10:00:00Z", references: Int = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "Images": [["Id": imageID, "RepoTags": ["example:latest"], "Size": 1200, "Containers": 0]],
            "Containers": [["Id": String(repeating: "b", count: 64), "Names": ["/running-db"], "State": "running", "SizeRw": 90]],
            "Volumes": [["Name": "database-data", "CreatedAt": created, "UsageData": ["Size": 5000, "RefCount": references]]],
            "BuildCache": [["ID": "cache-fixture", "Description": "Build layers", "Size": 800]]
        ])
    }

    @Test func parserShowsAllKindsAndNeverOffersRunningContainersOrBulkCachePrune() throws {
        let rows = try DockerClient.parseUsage(usage())
        #expect(rows.count == 4)
        #expect(rows.first?.kind == .volume)
        #expect(rows.first { $0.kind == .container }?.canRemove == false)
        #expect(rows.first { $0.kind == .buildCache }?.canRemove == false)
        #expect(rows.first { $0.kind == .image }?.canRemove == true)
    }

    @Test func referencedVolumesAreNotDeletable() throws {
        #expect(try DockerClient.parseUsage(usage(references: 1)).first { $0.kind == .volume }?.canRemove == false)
    }

    @Test func onlyTheLocalDesktopSocketIsAccepted() {
        let home = URL(fileURLWithPath: "/Users/fixture")
        #expect(DockerClient.acceptedSocket("unix:///Users/fixture/.docker/run/docker.sock", home: home) != nil)
        #expect(DockerClient.acceptedSocket("tcp://production:2375", home: home) == nil)
        #expect(DockerClient.acceptedSocket("ssh://production", home: home) == nil)
        #expect(DockerClient.acceptedSocket("unix:///Users/someone-else/.docker/run/docker.sock", home: home) == nil)
    }

    @Test func malformedIDsCannotBecomeDeletionArguments() {
        #expect(!DockerClient.validID("../database?force=true", kind: .volume))
        #expect(!DockerClient.validID("--all; rm -rf /", kind: .image))
        #expect(!DockerClient.validID("short", kind: .container))
    }

    @Test func deletionIsIndividualNeverForcedAndKeepsContainerVolumes() throws {
        let rows = try DockerClient.parseUsage(usage())
        let image = try #require(rows.first { $0.kind == .image })
        let path = try DockerClient.deletionPath(for: image)
        #expect(path.hasPrefix("/images/sha256%3A"))
        #expect(path.contains("force=false"))
        #expect(path.contains("noprune=true"))
        let container = DockerResource(kind: .container, objectID: String(repeating: "c", count: 64),
            name: "stopped", sizeBytes: 0, detail: "exited", canRemove: true)
        #expect(try DockerClient.deletionPath(for: container).hasSuffix("force=false&v=false"))
        let cache = try #require(rows.first { $0.kind == .buildCache })
        #expect(throws: (any Error).self) { try DockerClient.deletionPath(for: cache) }
    }

    @Test func changedDaemonNeverReceivesDelete() async throws {
        let data = try usage()
        let fixture = DockerFixture(usage: data, daemon: "different-daemon")
        let client = DockerClient(protections: DeletionProtection(fileURL: nil), request: { try await fixture.request($0, $1) })
        let item = try #require(try DockerClient.parseUsage(data).first { $0.kind == .image })
        do { try await client.remove(item, daemonID: "old-daemon", grant: nil); Issue.record("Changed daemon was accepted") }
        catch { #expect(await fixture.requests.allSatisfy { !$0.hasPrefix("DELETE") }) }
    }

    @Test func replacementVolumeMustBeReviewedAgain() async throws {
        let old = try #require(try DockerClient.parseUsage(usage()).first { $0.kind == .volume })
        let fixture = DockerFixture(usage: try usage(created: "2026-10-20T10:00:00Z"))
        let client = DockerClient(protections: DeletionProtection(fileURL: nil), request: { try await fixture.request($0, $1) })
        do { try await client.remove(old, daemonID: "local-fixture", grant: nil); Issue.record("Replacement volume was accepted") }
        catch { #expect(await fixture.requests.allSatisfy { !$0.hasPrefix("DELETE") }) }
    }

    @Test func protectedDockerObjectNeverDeletesWithoutGrant() async throws {
        let data = try usage()
        let item = try #require(try DockerClient.parseUsage(data).first { $0.kind == .image })
        let store = DeletionProtection(fileURL: nil)
        try store.protectDocker(key: item.protectionKey(daemonID: "local-fixture"), name: item.name)
        let fixture = DockerFixture(usage: data)
        let client = DockerClient(protections: store, request: { try await fixture.request($0, $1) })
        do { try await client.remove(item, daemonID: "local-fixture", grant: nil); Issue.record("Protected image was deleted") }
        catch { #expect(await fixture.requests.allSatisfy { !$0.hasPrefix("DELETE") }) }
    }

    @Test @MainActor func authenticatedFixtureRemovalDoesNotUnlockTheRecord() async throws {
        let data = try usage()
        let item = try #require(try DockerClient.parseUsage(data).first { $0.kind == .image })
        let key = item.protectionKey(daemonID: "local-fixture")
        let store = DeletionProtection(fileURL: nil)
        try store.protectDocker(key: key, name: item.name)
        let grant = try await ProtectionAuthentication.authorize(store: store, dockerKey: key, authenticate: { _ in true })
        let fixture = DockerFixture(usage: data)
        let client = DockerClient(protections: store, request: { try await fixture.request($0, $1) })
        try await client.remove(item, daemonID: "local-fixture", grant: grant)
        #expect(await fixture.requests.filter { $0.hasPrefix("DELETE") }.count == 1)
        #expect(!store.allows(dockerKey: key, grant: nil))
    }
}
