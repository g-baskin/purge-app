import Foundation

/// Lists the third-party apps in the Applications folders.
nonisolated enum InstalledAppIndex {
    struct BundleInfo: Sendable, Equatable {
        let bundleID: String
        let displayName: String
        let folderNames: [String]
        let version: String?
    }

    /// Real Info.plist files are a few KB; anything huge is refused unread.
    static let maxInfoPlistBytes = 2 * 1024 * 1024

    /// Reads `Contents/Info.plist` directly (not through `Bundle`, which caches
    /// per path and goes stale after an app is replaced). Returns `nil` for a
    /// missing, symlinked, oversized or malformed plist, or an invalid bundle ID.
    static func readInfo(at bundleURL: URL) -> BundleInfo? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: plistURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= maxInfoPlistBytes,
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String,
              AppUninstallPolicy.isValidBundleID(bundleID)
        else { return nil }

        let fileName = bundleURL.deletingPathExtension().lastPathComponent
        let candidates = [fileName, dict["CFBundleName"] as? String, dict["CFBundleDisplayName"] as? String]
        var folderNames: [String] = []
        for case let name? in candidates
        where AppUninstallPolicy.isUsableFolderName(name)
            && !folderNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            folderNames.append(name)
        }

        let version = (dict["CFBundleShortVersionString"] as? String).map { String($0.prefix(40)) }
        return BundleInfo(
            bundleID: bundleID,
            displayName: String(fileName.prefix(120)),
            folderNames: folderNames,
            version: version
        )
    }

    /// Third-party apps directly in each Applications folder or one vendor folder
    /// below. Skips Apple's apps, Purge itself, symlinks and unreadable bundles.
    /// Sizes are left `nil`; see `withMeasuredSizes`.
    static func scan(policy: AppUninstallPolicy) -> [InstalledApp] {
        var bundleURLs: [URL] = []
        for root in policy.applicationsRoots {
            for child in children(of: root) {
                if child.pathExtension.lowercased() == "app" {
                    bundleURLs.append(child)
                } else if AppUninstallPolicy.fileType(at: child) == .typeDirectory {
                    bundleURLs += children(of: child).filter { $0.pathExtension.lowercased() == "app" }
                }
            }
        }

        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for url in bundleURLs where seen.insert(url.standardizedFileURL.path).inserted {
            if let app = makeApp(at: url, policy: policy) {
                apps.append(app)
            }
        }
        return apps.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func makeApp(at url: URL, policy: AppUninstallPolicy) -> InstalledApp? {
        let std = url.standardizedFileURL
        guard AppUninstallPolicy.fileType(at: std) == .typeDirectory,
              let info = readInfo(at: std),
              !AppUninstallPolicy.isAppleOwned(info.bundleID.lowercased()),
              !policy.isPurge(path: std.path, bundleID: info.bundleID)
        else { return nil }

        let receipt = std.appendingPathComponent("Contents/_MASReceipt").path
        return InstalledApp(
            bundleURL: std,
            bundleID: info.bundleID,
            displayName: info.displayName,
            folderNames: info.folderNames,
            version: info.version,
            sizeBytes: nil,
            isAppStoreApp: FileManager.default.fileExists(atPath: receipt),
            canMoveBundle: AppUninstallPolicy.canMoveItem(at: std)
        )
    }

    static func withMeasuredSizes(_ apps: [InstalledApp]) -> [InstalledApp] {
        let sizes = FolderSizing.directorySizes(at: apps.map(\.bundleURL))
        return apps.map { app in
            var sized = app
            sized.sizeBytes = sizes[app.bundleURL.path] ?? 0
            return sized
        }
    }

    static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

/// Finds the files in `~/Library` that belong to one app.
nonisolated enum AppFootprintScanner {
    static func relatedItems(
        for app: InstalledApp,
        context: AppCatalogContext,
        policy: AppUninstallPolicy
    ) -> [AppRelatedItem] {
        var found: [(url: URL, kind: AppRelatedItemKind, match: AppMatchStrength, isDirectory: Bool)] = []
        for root in policy.libraryRoots {
            for child in InstalledAppIndex.children(of: root.url) {
                let std = child.standardizedFileURL
                // Cheap name check first; only matches are stat'ed.
                guard let match = policy.match(
                    childNamed: std.lastPathComponent, in: root, app: app, context: context
                ) else { continue }
                // Symlinks are skipped: their space belongs to whatever they point at.
                switch AppUninstallPolicy.fileType(at: std) {
                case .typeDirectory?: found.append((std, root.kind, match, true))
                case .typeRegular?: found.append((std, root.kind, match, false))
                default: continue
                }
            }
        }

        let directorySizes = FolderSizing.directorySizes(at: found.filter(\.isDirectory).map(\.url))
        let items = found.map { entry in
            AppRelatedItem(
                url: entry.url,
                kind: entry.kind,
                match: entry.match,
                sizeBytes: entry.isDirectory
                    ? directorySizes[entry.url.path] ?? 0
                    : FolderSizing.singleFileSize(at: entry.url)
            )
        }
        return items.sorted {
            if $0.match != $1.match { return $0.match == .bundleID }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.sizeBytes != $1.sizeBytes { return $0.sizeBytes > $1.sizeBytes }
            return $0.url.path < $1.url.path
        }
    }
}
