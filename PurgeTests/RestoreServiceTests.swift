import Foundation
import Testing
@testable import Purge

/// Fake home + Trash under a temp folder; never touches the real Trash.
private struct Sandbox {
    let root: URL
    let home: URL
    let trash: URL

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory
            .appendingPathComponent("PurgeRestoreTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        home = root.appendingPathComponent("home", isDirectory: true)
        trash = root.appendingPathComponent("home/.Trash", isDirectory: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    var service: RestoreService { RestoreService(trashRoots: [trash], allowedRoot: home) }

    /// Simulates a clean: the file lives in the Trash, history points back home.
    func trashedFile(_ relativeOriginal: String, contents: String = "x") throws -> TrashedPiece {
        let trashed = trash.appendingPathComponent(UUID().uuidString)
        try contents.write(to: trashed, atomically: true, encoding: .utf8)
        return TrashedPiece(
            originalPath: home.appendingPathComponent(relativeOriginal).path,
            trashedPath: trashed.path
        )
    }

    func item(_ pieces: [TrashedPiece]?) -> CleanupHistoryDeletedItemDTO {
        CleanupHistoryDeletedItemDTO(path: home.path + "/item", sizeBytes: 1, trashedPieces: pieces)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Put Back (RestoreService)")
struct RestoreServiceTests {
    @Test func restoresFileAndRecreatesMissingParent() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        let piece = try box.trashedFile("Library/Caches/App/data.bin", contents: "hello")
        let item = box.item([piece])

        #expect(box.service.availability(of: item) == .restorable)
        let report = box.service.restore([item])

        #expect(report.restoredCount == 1)
        #expect(try String(contentsOfFile: piece.originalPath, encoding: .utf8) == "hello")
        #expect(!FileManager.default.fileExists(atPath: piece.trashedPath))
        #expect(box.service.availability(of: item) == .noLongerInTrash)
    }

    @Test func neverOverwritesSomethingNewAtOriginalPath() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        let piece = try box.trashedFile("cache.db", contents: "old")
        try "new".write(toFile: piece.originalPath, atomically: true, encoding: .utf8)
        let item = box.item([piece])

        #expect(box.service.availability(of: item) == .conflict)
        let report = box.service.restore([item])

        #expect(report.conflictCount == 1)
        #expect(try String(contentsOfFile: piece.originalPath, encoding: .utf8) == "new")
        #expect(FileManager.default.fileExists(atPath: piece.trashedPath))
    }

    @Test func emptiedTrashIsReportedNotFailed() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        let piece = try box.trashedFile("gone.txt")
        try FileManager.default.removeItem(atPath: piece.trashedPath)
        let item = box.item([piece])

        #expect(box.service.availability(of: item) == .noLongerInTrash)
        #expect(box.service.restore([item]).missingCount == 1)
    }

    @Test func oldHistoryWithoutPiecesIsNotRestorable() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        #expect(box.service.availability(of: box.item(nil)) == .notRestorable)
        #expect(box.service.restore([box.item(nil)]) == RestoreReport())
    }

    @Test func contentsOnlyCleanRestoresEveryPiece() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        let a = try box.trashedFile("Caches/Folder/a")
        let b = try box.trashedFile("Caches/Folder/b")
        let report = box.service.restore([box.item([a, b])])
        #expect(report.restoredCount == 2)
        #expect(FileManager.default.fileExists(atPath: a.originalPath))
        #expect(FileManager.default.fileExists(atPath: b.originalPath))
    }

    @Test func refusesPathsOutsideTrashOrHome() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        // Source not in a Trash folder.
        let stray = box.home.appendingPathComponent("not-trash.txt")
        try "x".write(to: stray, atomically: true, encoding: .utf8)
        let notFromTrash = TrashedPiece(originalPath: box.home.path + "/dest", trashedPath: stray.path)
        #expect(box.service.restore(notFromTrash) == .refused)

        // Destination outside the allowed root, including via "..".
        let real = try box.trashedFile("ok")
        let escaping = TrashedPiece(originalPath: box.home.path + "/../escaped", trashedPath: real.trashedPath)
        #expect(box.service.restore(escaping) == .refused)

        // Destination inside the Trash itself.
        let intoTrash = TrashedPiece(originalPath: box.trash.path + "/x", trashedPath: real.trashedPath)
        #expect(box.service.restore(intoTrash) == .refused)

        #expect(FileManager.default.fileExists(atPath: real.trashedPath))
    }

    /// Uninstalled apps come back to an Applications folder, which sits outside home.
    @Test func restoresAppBundlesOnlyIntoApplicationsFolders() throws {
        let box = try Sandbox(); defer { box.cleanup() }
        let fm = FileManager.default
        let applications = box.root.appendingPathComponent("Applications", isDirectory: true)
        try fm.createDirectory(at: applications, withIntermediateDirectories: true)
        let service = RestoreService(
            trashRoots: [box.trash], allowedRoot: box.home, applicationsRoots: [applications]
        )

        func trashedBundle() throws -> String {
            let url = box.trash.appendingPathComponent("\(UUID().uuidString).app", isDirectory: true)
            try fm.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            return url.path
        }

        let directPath = try trashedBundle()
        let direct = TrashedPiece(originalPath: applications.path + "/Editor.app", trashedPath: directPath)
        #expect(service.restore(direct) == .restored)

        let vendorPath = try trashedBundle()
        let vendor = TrashedPiece(originalPath: applications.path + "/Vendor/Tool.app", trashedPath: vendorPath)
        #expect(service.restore(vendor) == .restored)

        let refusedOriginals = [
            applications.path + "/notes.txt",                    // not an app
            applications.path + "/Host.app/Contents/Inner.app", // inside another app
            box.root.path + "/Elsewhere/Editor.app",             // not an Applications folder
            applications.path + "/../Escaped.app"                // climbs out
        ]
        for original in refusedOriginals {
            let trashedPath = try trashedBundle()
            let outcome = service.restore(TrashedPiece(originalPath: original, trashedPath: trashedPath))
            #expect(outcome == .refused, "\(original) should be refused")
            #expect(fm.fileExists(atPath: trashedPath))
        }
    }

    /// Real round trip: FileDeleter records where it trashed things, and Put Back
    /// returns them. Uses a throwaway folder in Caches, like FileDeleterOffMainTests.
    @Test func realCleanCanBePutBack() async throws {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PurgeRestoreRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 256).write(to: dir.appendingPathComponent("payload.bin"))
        defer { try? fm.removeItem(at: dir) }

        let report = try await FileDeleter().deleteItems(at: [dir])
        let deleted = try #require(report.deletedItems.first)
        #expect(!deleted.trashedPieces.isEmpty)
        defer { deleted.trashedPieces.forEach { try? fm.removeItem(atPath: $0.trashedPath) } }

        let item = CleanupHistoryDeletedItemDTO(
            path: deleted.path, sizeBytes: deleted.sizeBytes, trashedPieces: deleted.trashedPieces
        )
        let service = RestoreService()
        #expect(service.availability(of: item) == .restorable)
        #expect(service.restore([item]).restoredCount == deleted.trashedPieces.count)
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("payload.bin").path))
    }

    @Test func historyDecodesWithAndWithoutPieces() throws {
        let legacy = #"{"path":"/a","sizeBytes":5}"#
        let decoded = try JSONDecoder().decode(CleanupHistoryDeletedItemDTO.self, from: Data(legacy.utf8))
        #expect(decoded.trashedPieces == nil)

        let withPieces = CleanupHistoryDeletedItemDTO(
            path: "/a", sizeBytes: 5,
            trashedPieces: [TrashedPiece(originalPath: "/a", trashedPath: "/t/a")]
        )
        let roundTrip = try JSONDecoder().decode(
            CleanupHistoryDeletedItemDTO.self,
            from: JSONEncoder().encode(withPieces)
        )
        #expect(roundTrip == withPieces)
    }
}
