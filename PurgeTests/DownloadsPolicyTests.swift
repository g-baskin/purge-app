import Foundation
import Testing
@testable import Purge

@Suite("Downloads review boundaries")
struct DownloadsPolicyTests {
    @Test func onlyImmediateRealDownloadsChildrenAreEligible() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("purge-downloads-\(UUID())")
        let root = base.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let file = root.appendingPathComponent("archive.zip")
        try Data("fixture".utf8).write(to: file)
        let folder = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let nested = folder.appendingPathComponent("work.txt")
        try Data("keep".utf8).write(to: nested)
        #expect(DownloadsPolicy.isEligible(file, root: root))
        #expect(DownloadsPolicy.isEligible(folder, root: root))
        #expect(!DownloadsPolicy.isEligible(root, root: root))
        #expect(!DownloadsPolicy.isEligible(nested, root: root))
        #expect(!DownloadsPolicy.isEligible(base, root: root))
    }

    @Test func symlinksCannotEscapeDownloadsBoundary() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("purge-download-links-\(UUID())")
        let root = base.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside.txt")
        try Data("keep".utf8).write(to: outside)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(!DownloadsPolicy.isEligible(link, root: root))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}
