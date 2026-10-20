import Foundation
import Testing
@testable import Purge

@Suite("Persistent authenticated deletion protection")
struct DeletionProtectionTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("purge-protection-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func recordsSurviveRestartAndProtectParentsAndChildren() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: file)
        let database = root.appendingPathComponent("locks.json")
        let store = DeletionProtection(fileURL: database)
        let record = try store.protect(url: file)
        let reopened = DeletionProtection(fileURL: database)
        #expect(try reopened.snapshot().first?.id == record.id)
        #expect(!reopened.allows(url: file, grant: nil))
        #expect(!reopened.allows(url: root, grant: nil))
        #expect(reopened.allows(url: root.appendingPathComponent("other.txt"), grant: nil))
        #expect(!reopened.allowsEmptyTrash(grant: nil))
    }

    @Test func componentBoundariesDoNotLockSimilarNames() {
        #expect(DeletionProtection.overlaps("/a/app/child", "/a/app"))
        #expect(!DeletionProtection.overlaps("/a/application", "/a/app"))
    }

    @Test func corruptProtectionFileBlocksDeletion() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("locks.json")
        try Data("not json".utf8).write(to: database)
        let store = DeletionProtection(fileURL: database)
        #expect(throws: (any Error).self) { try store.snapshot() }
        #expect(!store.allows(url: root.appendingPathComponent("anything"), grant: nil))
        #expect(!store.allows(dockerKey: "anything", grant: nil))
        #expect(!store.allowsEmptyTrash(grant: nil))
    }

    @Test func duplicateLockIDsCannotAuthorizeUnrelatedRecords() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("locks.json")
        let id = UUID()
        let records = [ProtectedItem(id: id, name: "one", path: nil, bookmark: nil, dockerKey: "one"),
                       ProtectedItem(id: id, name: "two", path: nil, bookmark: nil, dockerKey: "two")]
        try JSONEncoder().encode(records).write(to: database)
        let store = DeletionProtection(fileURL: database)
        #expect(throws: (any Error).self) { try store.snapshot() }
        #expect(!store.allows(dockerKey: "two", grant: nil))
    }

    @Test func unreadableProtectionFileCannotLookLikeAnEmptyStore() throws {
        let root = try folder()
        let database = root.appendingPathComponent("locks.json")
        try Data("[]".utf8).write(to: database)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: database.path)
        let store = DeletionProtection(fileURL: database)
        #expect(throws: (any Error).self) { try store.snapshot() }
        #expect(!store.allowsEmptyTrash(grant: nil))
    }

    @Test @MainActor func authenticationIsScopedAndDoesNotRemoveLocks() async throws {
        let store = DeletionProtection(fileURL: nil)
        let first = URL(fileURLWithPath: "/tmp/purge-protected-a")
        let second = URL(fileURLWithPath: "/tmp/purge-protected-b")
        try store.protect(url: first)
        try store.protect(url: second)
        let grant = try await ProtectionAuthentication.authorize(store: store, urls: [first], authenticate: { _ in true })
        #expect(store.allows(url: first, grant: grant))
        #expect(!store.allows(url: second, grant: grant))
        #expect(!store.allows(url: first, grant: nil))
        #expect(try store.snapshot().count == 2)
        // Adding a new overlapping lock after approval invalidates that approval for the new lock.
        try store.protect(url: URL(fileURLWithPath: "/tmp"))
        #expect(!store.allows(url: first, grant: grant))
    }

    @Test @MainActor func cancelledAuthenticationLeavesEverythingLocked() async throws {
        let store = DeletionProtection(fileURL: nil)
        let file = URL(fileURLWithPath: "/tmp/purge-cancelled-lock")
        try store.protect(url: file)
        do {
            _ = try await ProtectionAuthentication.authorize(store: store, urls: [file], authenticate: { _ in false })
            Issue.record("Cancelled authentication must not issue a grant")
        } catch { #expect(!store.allows(url: file, grant: nil)) }
    }

    @Test @MainActor func backgroundCleaningDoesNotAuthenticate() async throws {
        let store = DeletionProtection(fileURL: nil)
        let file = URL(fileURLWithPath: "/tmp/purge-background-lock")
        try store.protect(url: file)
        let grant = try await ProtectionAuthentication.authorize(store: store, urls: [file], interactive: false,
            authenticate: { _ in Issue.record("Background cleanup must never prompt"); return true })
        #expect(grant == nil)
        #expect(!store.allows(url: file, grant: grant))
    }

    @Test func engineCannotDeleteProtectedItemOrParentWithoutAuthentication() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: file)
        let store = DeletionProtection(fileURL: nil)
        try store.protect(url: file)
        let deleter = FileDeleter(protectionStore: store)
        let report = try await deleter.deleteUserSelectedFiles(at: [root], allowsProtectedAuthentication: false)
        #expect(report.deletedItems.isEmpty)
        #expect(report.skippedItems.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let cleanup = try await deleter.deleteItems(at: [file], allowsProtectedAuthentication: false)
        #expect(cleanup.deletedItems.isEmpty)
        #expect(cleanup.skippedItems.count == 1)
    }

    @Test func privilegedRouteCannotBypassProtection() async throws {
        let store = DeletionProtection(fileURL: nil)
        let url = URL(fileURLWithPath: "/tmp/purge-no-helper-bypass")
        try store.protect(url: url)
        let result = await PrivilegedUninstall.moveToTrash([url], protectionStore: store)
        #expect(result.moved.isEmpty)
        #expect(result.failed == [url])
        #expect(!result.helperAvailable)
    }

    @Test @MainActor func removingProtectionRequiresItsAuthenticatedGrant() async throws {
        let store = DeletionProtection(fileURL: nil)
        let record = try store.protectDocker(key: "fixture-docker", name: "Database")
        let grant = try #require(try await ProtectionAuthentication.authorize(store: store, items: [record], authenticate: { _ in true }))
        try store.remove(record, grant: grant)
        #expect(try store.snapshot().isEmpty)
    }

    @Test func dockerVirtualDisksCannotBeRemovedAsOrdinaryFiles() {
        #expect(FileDeleter.isManagedDockerData(URL(fileURLWithPath: "/tmp/Docker.raw")))
        #expect(FileDeleter.isManagedDockerData(DockerClient.dataRoot.appendingPathComponent("Data/vms/0/data/Docker.raw")))
    }
}
