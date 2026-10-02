import Foundation

/// A `~/Library` folder whose direct children may belong to individual apps.
nonisolated struct AppLibraryRoot: Sendable, Hashable {
    /// How a child's name encodes the owning app's bundle ID.
    enum Pattern: Sendable, Hashable {
        /// `com.example.app` (also `com.example.app.helper`).
        case directory
        /// `com.example.app.plist`.
        case plist
        /// `com.example.app.savedState`.
        case savedState
        /// `com.example.app.binarycookies`.
        case binaryCookies
        /// `group.com.example.app` or `TEAMID1234.com.example.app`.
        case groupContainer
    }

    let url: URL
    let kind: AppRelatedItemKind
    let pattern: Pattern
    /// Also match folders named after the app (`Application Support/Slack`).
    let matchesFolderNames: Bool
}

/// The rules for what the app uninstaller may move to the Trash.
///
/// Separate from `DeletionSafetyPolicy` on purpose: that policy guards cache
/// cleaning and refuses `~/Library/Preferences` outright, while uninstalling an
/// app legitimately removes its own settings file.
///
/// Fails closed throughout. Bundle IDs and names come from other apps' Info.plist
/// files, so they are untrusted: Purge never builds a path from them. It lists
/// each known folder and compares names, so every candidate is a direct child of
/// a known folder by construction.
nonisolated struct AppUninstallPolicy: Sendable {
    let home: URL
    let applicationsRoots: [URL]
    let ownBundleID: String?
    let ownBundlePath: String?

    init(home: URL, applicationsRoots: [URL], ownBundleID: String?, ownBundlePath: String?) {
        self.home = home.standardizedFileURL
        self.applicationsRoots = applicationsRoots.map(\.standardizedFileURL)
        self.ownBundleID = ownBundleID
        self.ownBundlePath = ownBundlePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
    }

    static func live() -> AppUninstallPolicy {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppUninstallPolicy(
            home: home,
            applicationsRoots: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true)
            ],
            ownBundleID: Bundle.main.bundleIdentifier,
            ownBundlePath: Bundle.main.bundleURL.path
        )
    }

    var libraryRoots: [AppLibraryRoot] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        func root(
            _ relative: String,
            _ kind: AppRelatedItemKind,
            _ pattern: AppLibraryRoot.Pattern,
            names: Bool = false
        ) -> AppLibraryRoot {
            AppLibraryRoot(
                url: library.appendingPathComponent(relative, isDirectory: true).standardizedFileURL,
                kind: kind,
                pattern: pattern,
                matchesFolderNames: names
            )
        }
        return [
            root("Application Support", .appData, .directory, names: true),
            root("Containers", .sandboxData, .directory),
            root("Group Containers", .sharedData, .groupContainer),
            root("Preferences", .settings, .plist),
            root("Preferences/ByHost", .settings, .plist),
            root("Caches", .cache, .directory, names: true),
            root("HTTPStorages", .webData, .directory),
            root("WebKit", .webData, .directory),
            root("Cookies", .cookies, .binaryCookies),
            root("Logs", .logs, .directory, names: true),
            root("Saved Application State", .savedState, .savedState),
            root("LaunchAgents", .backgroundHelper, .plist),
            root("Application Scripts", .scripts, .directory)
        ]
    }

    // MARK: - Identity checks

    /// Reverse-DNS with only letters, digits, `-` and `_` between dots. Rejects
    /// empty components, so `..` and `/` can never appear.
    static func isValidBundleID(_ id: String) -> Bool {
        guard (3...255).contains(id.utf8.count) else { return false }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (byte >= 0x30 && byte <= 0x39) // 0-9
                    || (byte >= 0x41 && byte <= 0x5A) // A-Z
                    || (byte >= 0x61 && byte <= 0x7A) // a-z
                    || byte == 0x2D || byte == 0x5F // - _
            }
        }
    }

    static func isAppleOwned(_ lowercasedName: String) -> Bool {
        lowercasedName == "com.apple" || lowercasedName.hasPrefix("com.apple.")
    }

    /// Vendor and shared folder names many apps write into, never one app's own.
    private static let genericFolderNames: Set<String> = [
        "adobe", "apple", "google", "jetbrains", "microsoft", "mozilla", "electron",
        "chromium", "crashreporter", "crashpad", "shared", "common", "default", "data",
        "cache", "caches", "logs", "temp", "tmp", "library", "application support",
        "preferences", "containers", "updater", "helper", "plugins", "addons",
        "extensions", "fonts", "scripts", "python", "java", "node"
    ]

    /// Whether `name` is specific enough to match a folder by name alone.
    static func isUsableFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, (3...100).contains(trimmed.count) else { return false }
        guard !trimmed.hasPrefix("."), !trimmed.contains("/"), !trimmed.contains(":") else { return false }
        return !genericFolderNames.contains(trimmed.lowercased())
    }

    private static func componentCount(_ id: String) -> Int {
        id.split(separator: ".").count
    }

    /// The bundle-ID part of a child's name for `pattern`, or `nil` when the name
    /// doesn't have that shape. Expects a lowercased name.
    static func identifierPart(of name: String, pattern: AppLibraryRoot.Pattern) -> String? {
        func stripping(_ suffix: String) -> String? {
            guard name.hasSuffix(suffix), name.count > suffix.count else { return nil }
            return String(name.dropLast(suffix.count))
        }
        switch pattern {
        case .directory:
            return name
        case .plist:
            return stripping(".plist")
        case .savedState:
            return stripping(".savedstate")
        case .binaryCookies:
            return stripping(".binarycookies")
        case .groupContainer:
            if name.hasPrefix("group."), name.count > 6 { return String(name.dropFirst(6)) }
            let parts = name.split(separator: ".", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].count == 10,
                  parts[0].utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) })
            else { return nil }
            return String(parts[1])
        }
    }

    func isPurge(path: String, bundleID: String) -> Bool {
        if let ownBundlePath, URL(fileURLWithPath: path).standardizedFileURL.path == ownBundlePath { return true }
        if let ownBundleID, ownBundleID.caseInsensitiveCompare(bundleID) == .orderedSame { return true }
        return false
    }

    // MARK: - Related files

    /// Whether the child `name` of `root` belongs to `app`. `nil` means it doesn't,
    /// or might belong to Apple, another installed app, or another copy of this one.
    func match(
        childNamed name: String,
        in root: AppLibraryRoot,
        app: InstalledApp,
        context: AppCatalogContext
    ) -> AppMatchStrength? {
        guard Self.isValidBundleID(app.bundleID) else { return nil }
        let id = app.bundleID.lowercased()
        guard !Self.isAppleOwned(id) else { return nil }
        // Another copy of the app shares these files; removing one copy keeps them.
        guard !context.otherBundleIDs.contains(id) else { return nil }
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }

        let lower = name.lowercased()
        guard !Self.isAppleOwned(lower) else { return nil }

        if let part = Self.identifierPart(of: lower, pattern: root.pattern), !Self.isAppleOwned(part) {
            if part == id { return .bundleID }
            // `com.example.app.helper` is the app's too, but only for IDs with a
            // product component: a two-part ID like `com.example` would sweep up
            // every app from that vendor.
            if Self.componentCount(id) >= 3, part.hasPrefix(id + ".") {
                let ownedByMoreSpecificApp = context.otherBundleIDs.contains { other in
                    other.count > id.count && (part == other || part.hasPrefix(other + "."))
                }
                if !ownedByMoreSpecificApp { return .bundleID }
            }
        }

        if root.matchesFolderNames,
           !context.otherFolderNames.contains(lower),
           app.folderNames.contains(where: { Self.isUsableFolderName($0) && $0.lowercased() == lower }) {
            return .name
        }
        return nil
    }

    /// Delete-time gate for a related file: re-checked right before it moves, so a
    /// swap since the scan (a new symlink, a renamed folder) is refused.
    func isEligibleRelatedItem(_ url: URL, app: InstalledApp, context: AppCatalogContext) -> Bool {
        let std = url.standardizedFileURL
        let parentPath = std.deletingLastPathComponent().path
        guard let root = libraryRoots.first(where: { $0.url.path == parentPath }) else { return false }
        guard let type = Self.fileType(at: std),
              type == .typeDirectory || type == .typeRegular
        else { return false }
        return match(childNamed: std.lastPathComponent, in: root, app: app, context: context) != nil
    }

    // MARK: - App bundles

    enum AppBundleRefusal: Equatable, Sendable {
        case notAnApp
        case outsideApplicationsFolders
        case appleApp
        case isPurge
        case changedSinceScan
        case needsAdminPassword

        var explanation: String {
            switch self {
            case .notAnApp: return "This isn't an app Purge can remove."
            case .outsideApplicationsFolders: return "Purge only removes apps from your Applications folders."
            case .appleApp: return "Apps that come with macOS can't be removed."
            case .isPurge: return "Purge can't remove itself."
            case .changedSinceScan: return "This app changed since Purge looked at it. Scan again."
            case .needsAdminPassword:
                return "macOS needs an administrator password to remove this app, so Purge leaves it alone. Drag it to the Trash in Finder instead."
            }
        }
    }

    /// Directly inside an Applications folder, or one vendor folder below it
    /// (`/Applications/Vendor/App.app`). Never inside another app.
    func isInApplicationsFolder(_ url: URL) -> Bool {
        let std = url.standardizedFileURL
        let parent = std.deletingLastPathComponent()
        let rootPaths = Set(applicationsRoots.map(\.path))
        if rootPaths.contains(parent.path) { return true }
        return parent.pathExtension.lowercased() != "app"
            && rootPaths.contains(parent.deletingLastPathComponent().path)
    }

    /// `nil` when the bundle may be moved to the Trash. Pass the bundle ID seen at
    /// scan time to refuse a bundle that was replaced since.
    func refusalForAppBundle(_ url: URL, expectedBundleID: String?) -> AppBundleRefusal? {
        let std = url.standardizedFileURL
        guard std.pathExtension.lowercased() == "app" else { return .notAnApp }
        guard isInApplicationsFolder(std) else { return .outsideApplicationsFolders }
        // Not traversed: a symlinked "app" is refused rather than followed.
        guard Self.fileType(at: std) == .typeDirectory else { return .notAnApp }
        guard let info = InstalledAppIndex.readInfo(at: std) else { return .notAnApp }
        if let expectedBundleID, info.bundleID.caseInsensitiveCompare(expectedBundleID) != .orderedSame {
            return .changedSinceScan
        }
        if Self.isAppleOwned(info.bundleID.lowercased()) { return .appleApp }
        if isPurge(path: std.path, bundleID: info.bundleID) { return .isPurge }
        guard Self.canMoveItem(at: std) else { return .needsAdminPassword }
        return nil
    }

    /// Moving a folder to the Trash needs write access to its parent and, because
    /// the move rewrites the folder's own entry, to the folder itself. Root-owned
    /// bundles (App Store apps) fail this.
    static func canMoveItem(at url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: url.deletingLastPathComponent().path) else { return false }
        if fileType(at: url) == .typeDirectory {
            return fm.isWritableFile(atPath: url.path)
        }
        return true
    }

    /// The item's own type; a symlink reports `.typeSymbolicLink`, never its target's.
    static func fileType(at url: URL) -> FileAttributeType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.type] as? FileAttributeType
    }
}
