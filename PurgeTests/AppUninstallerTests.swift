import Foundation
import Testing
@testable import Purge

/// A fake Applications folder and home folder under a temp directory. Paths are
/// resolved up front (`/var` → `/private/var`) so they compare exactly, as the real
/// `/Applications` and `~/Library` do.
private struct UninstallSandbox {
    let root: URL
    let applications: URL
    let home: URL

    init() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("PurgeUninstallTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath().standardizedFileURL
        applications = root.appendingPathComponent("Applications", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        try fm.createDirectory(at: applications, withIntermediateDirectories: true)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
    }

    var library: URL { home.appendingPathComponent("Library", isDirectory: true) }

    var policy: AppUninstallPolicy {
        AppUninstallPolicy(
            home: home,
            applicationsRoots: [applications],
            ownBundleID: "com.purge.self",
            ownBundlePath: nil
        )
    }

    @discardableResult
    func makeApp(
        _ name: String,
        bundleID: String,
        in folder: URL? = nil,
        plist extra: [String: Any] = [:]
    ) throws -> URL {
        let app = (folder ?? applications).appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": "1.0"
        ]
        plist.merge(extra) { $1 }
        try writePlist(plist, to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 1, count: 4096).write(to: contents.appendingPathComponent("payload"))
        return app
    }

    func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }

    /// Creates `~/Library/<relative>` as a folder with one file, or as a file.
    @discardableResult
    func makeLibraryItem(_ relative: String, isDirectory: Bool = true) throws -> URL {
        let url = library.appendingPathComponent(relative)
        let fm = FileManager.default
        if isDirectory {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 2, count: 2048).write(to: url.appendingPathComponent("data.bin"))
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 3, count: 512).write(to: url)
        }
        return url.standardizedFileURL
    }

    func app(_ url: URL) throws -> InstalledApp {
        try #require(InstalledAppIndex.makeApp(at: url, policy: policy))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private func app(
    _ bundleID: String,
    folderNames: [String] = [],
    path: String = "/Applications/Test.app"
) -> InstalledApp {
    InstalledApp(
        bundleURL: URL(fileURLWithPath: path),
        bundleID: bundleID,
        displayName: "Test",
        folderNames: folderNames,
        version: nil,
        sizeBytes: nil,
        isAppStoreApp: false,
        canMoveBundle: true
    )
}

@Suite("Uninstaller: identity rules")
struct AppUninstallIdentityTests {
    @Test(arguments: ["com.example.app", "com.Example.App-Beta", "org.mozilla.firefox", "io.a_b.c9"])
    func acceptsReverseDNSBundleIDs(_ id: String) {
        #expect(AppUninstallPolicy.isValidBundleID(id))
    }

    @Test(arguments: [
        "", "app", "com..app", ".com.app", "com.app.", "../evil", "com/evil.app",
        "com.example.app/..", "com.exa mple.app", "com.exämple.app", "com.example.*"
    ])
    func rejectsAnythingThatIsNotAPlainBundleID(_ id: String) {
        #expect(!AppUninstallPolicy.isValidBundleID(id))
    }

    @Test func folderNamesMustBeSpecific() {
        #expect(AppUninstallPolicy.isUsableFolderName("Slack"))
        #expect(AppUninstallPolicy.isUsableFolderName("Visual Studio Code"))
        for name in ["Google", "Data", "Caches", "ab", ".Slack", "Sl/ack", " Slack", "Slack "] {
            #expect(!AppUninstallPolicy.isUsableFolderName(name), "\(name) should be refused")
        }
    }

    @Test func extractsTheBundleIDPartOfEachNameShape() {
        typealias P = AppLibraryRoot.Pattern
        #expect(AppUninstallPolicy.identifierPart(of: "com.example.app.plist", pattern: P.plist) == "com.example.app")
        #expect(AppUninstallPolicy.identifierPart(of: "com.example.app", pattern: P.plist) == nil)
        #expect(AppUninstallPolicy.identifierPart(of: "com.example.app.savedstate", pattern: P.savedState) == "com.example.app")
        #expect(AppUninstallPolicy.identifierPart(of: "group.com.example.app", pattern: P.groupContainer) == "com.example.app")
        #expect(AppUninstallPolicy.identifierPart(of: "abcde12345.com.example.app", pattern: P.groupContainer) == "com.example.app")
        #expect(AppUninstallPolicy.identifierPart(of: "abc.com.example.app", pattern: P.groupContainer) == nil)
    }
}

@Suite("Uninstaller: which files belong to an app")
struct AppUninstallMatchTests {
    let policy = AppUninstallPolicy(
        home: URL(fileURLWithPath: "/Users/tester"),
        applicationsRoots: [URL(fileURLWithPath: "/Applications")],
        ownBundleID: nil,
        ownBundlePath: nil
    )

    private func root(_ relative: String) -> AppLibraryRoot {
        let path = "/Users/tester/Library/\(relative)"
        return policy.libraryRoots.first { $0.url.path == path }!
    }

    @Test func matchesTheAppsOwnBundleIDIgnoringCase() {
        let slack = app("com.tinyspeck.slackmacgap")
        #expect(policy.match(childNamed: "com.tinyspeck.slackmacgap", in: root("Containers"), app: slack, context: .init()) == .bundleID)
        #expect(policy.match(childNamed: "COM.Tinyspeck.SlackMacGap", in: root("Caches"), app: slack, context: .init()) == .bundleID)
        #expect(policy.match(childNamed: "com.tinyspeck.slackmacgap.plist", in: root("Preferences"), app: slack, context: .init()) == .bundleID)
        #expect(policy.match(childNamed: "com.tinyspeck.slackmacgap.savedState", in: root("Saved Application State"), app: slack, context: .init()) == .bundleID)
        #expect(policy.match(childNamed: "group.com.tinyspeck.slackmacgap", in: root("Group Containers"), app: slack, context: .init()) == .bundleID)
    }

    @Test func includesTheAppsHelpersButNotOtherAppsFromTheSameVendor() {
        let pro = app("com.example.editor")
        #expect(policy.match(childNamed: "com.example.editor.helper", in: root("Caches"), app: pro, context: .init()) == .bundleID)
        #expect(policy.match(childNamed: "com.example.editorial", in: root("Caches"), app: pro, context: .init()) == nil)
        #expect(policy.match(childNamed: "com.example.other", in: root("Caches"), app: pro, context: .init()) == nil)

        // A two-part ID would claim the whole vendor, so its prefix never counts.
        let vendor = app("com.example")
        #expect(policy.match(childNamed: "com.example.other", in: root("Caches"), app: vendor, context: .init()) == nil)
        #expect(policy.match(childNamed: "com.example", in: root("Caches"), app: vendor, context: .init()) == .bundleID)
    }

    @Test func leavesFilesOfAMoreSpecificInstalledApp() {
        let editor = app("com.example.editor")
        let context = AppCatalogContext(otherBundleIDs: ["com.example.editor.pro"])
        #expect(policy.match(childNamed: "com.example.editor.pro", in: root("Containers"), app: editor, context: context) == nil)
        #expect(policy.match(childNamed: "com.example.editor.pro.helper", in: root("Containers"), app: editor, context: context) == nil)
        #expect(policy.match(childNamed: "com.example.editor.helper", in: root("Containers"), app: editor, context: context) == .bundleID)
    }

    @Test func matchesNothingWhenAnotherCopyIsInstalled() {
        let editor = app("com.example.editor")
        let context = AppCatalogContext(otherBundleIDs: ["com.example.editor"])
        #expect(policy.match(childNamed: "com.example.editor", in: root("Containers"), app: editor, context: context) == nil)
    }

    @Test func neverMatchesApplesFiles() {
        let apple = app("com.apple.Safari")
        #expect(policy.match(childNamed: "com.apple.Safari", in: root("Containers"), app: apple, context: .init()) == nil)
        let thirdParty = app("com.example.editor", folderNames: ["com.apple.editor"])
        #expect(policy.match(childNamed: "com.apple.editor", in: root("Application Support"), app: thirdParty, context: .init()) == nil)
    }

    @Test func namesOnlyMatchWhereAppsUseThemAndNoOtherAppDoes() {
        let notion = app("notion.id", folderNames: ["Notion"])
        #expect(policy.match(childNamed: "Notion", in: root("Application Support"), app: notion, context: .init()) == .name)
        #expect(policy.match(childNamed: "notion", in: root("Logs"), app: notion, context: .init()) == .name)
        // Containers are only ever named by bundle ID.
        #expect(policy.match(childNamed: "Notion", in: root("Containers"), app: notion, context: .init()) == nil)
        // Another installed app uses the same name: leave it alone.
        let shared = AppCatalogContext(otherFolderNames: ["notion"])
        #expect(policy.match(childNamed: "Notion", in: root("Application Support"), app: notion, context: shared) == nil)
    }

    @Test func refusesHiddenAndPathLikeNames() {
        let editor = app("com.example.editor", folderNames: ["Editor"])
        for name in [".Editor", "", "Editor/../x", "com.example.editor/x"] {
            #expect(policy.match(childNamed: name, in: root("Application Support"), app: editor, context: .init()) == nil)
        }
    }
}

@Suite("Uninstaller: app bundles and scanning")
struct AppUninstallBundleTests {
    @Test func listsThirdPartyAppsIncludingVendorFolders() throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        try box.makeApp("Zebra", bundleID: "com.example.zebra")
        let vendor = box.applications.appendingPathComponent("Example Suite", isDirectory: true)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        try box.makeApp("Alpha", bundleID: "com.example.alpha", in: vendor)
        try box.makeApp("Safari", bundleID: "com.apple.Safari")
        try box.makeApp("Purge", bundleID: "com.purge.self")
        try box.makeApp("Broken", bundleID: "../evil")
        // A symlinked "app" is never listed or followed.
        let real = try box.makeApp("Real", bundleID: "com.example.real", in: box.root)
        try FileManager.default.createSymbolicLink(
            at: box.applications.appendingPathComponent("Linked.app"),
            withDestinationURL: real
        )

        let apps = InstalledAppIndex.scan(policy: box.policy)
        let names = apps.map { $0.displayName }
        let allMovable = apps.allSatisfy { $0.canMoveBundle }
        #expect(names == ["Alpha", "Zebra"])
        #expect(allMovable)
        #expect(apps.first?.version == "1.0")
    }

    @Test func refusesBundlesThatAreNotSafeToMove() throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let policy = box.policy
        let good = try box.makeApp("Good", bundleID: "com.example.good")
        #expect(policy.refusalForAppBundle(good, expectedBundleID: "com.example.good") == nil)

        // Replaced since the scan.
        #expect(policy.refusalForAppBundle(good, expectedBundleID: "com.example.other") == .changedSinceScan)

        let apple = try box.makeApp("Pages", bundleID: "com.apple.iWork.Pages")
        #expect(policy.refusalForAppBundle(apple, expectedBundleID: nil) == .appleApp)

        let me = try box.makeApp("Purge", bundleID: "com.purge.self")
        #expect(policy.refusalForAppBundle(me, expectedBundleID: nil) == .isPurge)

        let outside = try box.makeApp("Elsewhere", bundleID: "com.example.elsewhere", in: box.root)
        #expect(policy.refusalForAppBundle(outside, expectedBundleID: nil) == .outsideApplicationsFolders)

        let nested = try box.makeApp("Inner", bundleID: "com.example.inner", in: good)
        #expect(policy.refusalForAppBundle(nested, expectedBundleID: nil) == .outsideApplicationsFolders)

        let link = box.applications.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(policy.refusalForAppBundle(link, expectedBundleID: nil) == .notAnApp)

        let notApp = box.applications.appendingPathComponent("Notes.txt")
        try Data("x".utf8).write(to: notApp)
        #expect(policy.refusalForAppBundle(notApp, expectedBundleID: nil) == .notAnApp)
    }

    @Test func refusesOversizedOrSymlinkedInfoPlists() throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let big = try box.makeApp("Big", bundleID: "com.example.big")
        let bigPlist = big.appendingPathComponent("Contents/Info.plist")
        try Data(repeating: 0x20, count: InstalledAppIndex.maxInfoPlistBytes + 1).write(to: bigPlist)
        #expect(InstalledAppIndex.readInfo(at: big) == nil)

        let linked = try box.makeApp("Linked", bundleID: "com.example.linked")
        let linkedPlist = linked.appendingPathComponent("Contents/Info.plist")
        let elsewhere = box.root.appendingPathComponent("elsewhere.plist")
        try box.writePlist(["CFBundleIdentifier": "com.example.linked"], to: elsewhere)
        try FileManager.default.removeItem(at: linkedPlist)
        try FileManager.default.createSymbolicLink(at: linkedPlist, withDestinationURL: elsewhere)
        #expect(InstalledAppIndex.readInfo(at: linked) == nil)
    }

    @Test func findsTheAppsFilesAndOnlyThose() throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let bundle = try box.makeApp("Editor", bundleID: "com.example.editor")
        let container = try box.makeLibraryItem("Containers/com.example.editor")
        let prefs = try box.makeLibraryItem("Preferences/com.example.editor.plist", isDirectory: false)
        let support = try box.makeLibraryItem("Application Support/Editor")
        try box.makeLibraryItem("Application Support/com.example.other")
        try box.makeLibraryItem("Caches/com.apple.Safari")
        // Only direct children count: a match nested inside another folder is ignored.
        try box.makeLibraryItem("Caches/Other Vendor/com.example.editor")
        // A symlink named like the app is skipped, never followed.
        let target = try box.makeLibraryItem("Unrelated")
        try FileManager.default.createSymbolicLink(
            at: box.library.appendingPathComponent("Caches/com.example.editor"),
            withDestinationURL: target
        )

        let items = AppFootprintScanner.relatedItems(
            for: try box.app(bundle),
            context: .init(),
            policy: box.policy
        )
        let foundPaths = Set(items.map { $0.url.path })
        #expect(foundPaths == [container.path, prefs.path, support.path])
        #expect(items.first { $0.url == support }?.match == .name)
        #expect(items.first { $0.url == support }?.isSelectedByDefault == false)
        #expect(items.first { $0.url == container }?.isSelectedByDefault == true)
        #expect(items.allSatisfy { $0.sizeBytes > 0 })
    }
}

@Suite("Uninstaller: moving to the Trash")
struct AppUninstallDeletionTests {
    @Test func uninstallsAppAndFilesAndCanPutThemBack() async throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let bundle = try box.makeApp("Editor", bundleID: "com.example.editor")
        let container = try box.makeLibraryItem("Containers/com.example.editor")
        let prefs = try box.makeLibraryItem("Preferences/com.example.editor.plist", isDirectory: false)
        let app = try box.app(bundle)
        let items = AppFootprintScanner.relatedItems(for: app, context: .init(), policy: box.policy)

        let report = await FileDeleter().uninstallApp(
            app, includeAppBundle: true, relatedItems: items, context: .init(), policy: box.policy
        )
        let pieces = report.deletedItems.flatMap(\.trashedPieces)
        defer { pieces.forEach { try? FileManager.default.removeItem(atPath: $0.trashedPath) } }

        let fm = FileManager.default
        #expect(report.failedItems.isEmpty)
        #expect(report.deletedItems.count == 3)
        #expect(pieces.count == 3)
        for url in [bundle, container, prefs] {
            #expect(!fm.fileExists(atPath: url.path), "\(url.lastPathComponent) should be in the Trash")
        }

        // Put Back works for uninstalls too.
        let history = report.deletedItems.map {
            CleanupHistoryDeletedItemDTO(path: $0.path, sizeBytes: $0.sizeBytes, trashedPieces: $0.trashedPieces)
        }
        // Home and Applications are separate folders, as on a real Mac.
        let service = RestoreService(allowedRoot: box.home, applicationsRoots: [box.applications])
        let restored = service.restore(history)
        #expect(restored.restoredCount == 3)
        for url in [bundle, container, prefs] {
            #expect(fm.fileExists(atPath: url.path))
        }
    }

    @Test func keepsTheAppsFilesWhenTheAppItselfIsRefused() async throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let bundle = try box.makeApp("Editor", bundleID: "com.example.editor")
        let container = try box.makeLibraryItem("Containers/com.example.editor")
        let app = try box.app(bundle)
        let items = AppFootprintScanner.relatedItems(for: app, context: .init(), policy: box.policy)
        // The bundle is swapped for a different app after the review.
        try box.writePlist(
            ["CFBundleIdentifier": "com.example.impostor"],
            to: bundle.appendingPathComponent("Contents/Info.plist")
        )

        let report = await FileDeleter().uninstallApp(
            app, includeAppBundle: true, relatedItems: items, context: .init(), policy: box.policy
        )

        #expect(report.deletedItems.isEmpty)
        #expect(FileManager.default.fileExists(atPath: bundle.path))
        #expect(FileManager.default.fileExists(atPath: container.path))
        #expect(report.userVisibleFailures.count == 1)
    }

    @Test func refusesAFileSwappedForASymlinkAfterReview() async throws {
        let box = try UninstallSandbox(); defer { box.cleanup() }
        let bundle = try box.makeApp("Editor", bundleID: "com.example.editor")
        let cache = try box.makeLibraryItem("Caches/com.example.editor")
        let app = try box.app(bundle)
        let items = AppFootprintScanner.relatedItems(for: app, context: .init(), policy: box.policy)
        let precious = try box.makeLibraryItem("Precious")
        try FileManager.default.removeItem(at: cache)
        try FileManager.default.createSymbolicLink(at: cache, withDestinationURL: precious)

        let report = await FileDeleter().uninstallApp(
            app, includeAppBundle: false, relatedItems: items, context: .init(), policy: box.policy
        )

        #expect(report.deletedItems.isEmpty)
        #expect(report.skippedItems.count == 1)
        #expect(FileManager.default.fileExists(atPath: precious.appendingPathComponent("data.bin").path))
    }

    @Test func appManagementBlocksOpenSettings() {
        #expect(CleanFailureReason.needsAppManagement.showsOpenSettings)
        #expect(!CleanFailureReason.needsAppManagement.showsRetry)
    }
}
