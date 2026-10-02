import Foundation

/// An app bundle found in an Applications folder, described by its own Info.plist.
nonisolated struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: String { bundleURL.path }

    let bundleURL: URL
    let bundleID: String
    /// What Finder shows: the bundle's file name without `.app`.
    let displayName: String
    /// Names the app may give its own folders (`Application Support/Slack`). Only
    /// names that pass `AppUninstallPolicy.isUsableFolderName` are kept.
    let folderNames: [String]
    let version: String?
    /// `nil` until measured; the list appears first and sizes fill in after.
    var sizeBytes: Int64?
    let isAppStoreApp: Bool
    /// `false` when moving the bundle needs an administrator password (it belongs to
    /// another user, as App Store apps belong to root). Purge never asks for one.
    let canMoveBundle: Bool
}

/// How sure Purge is that a file belongs to the app.
nonisolated enum AppMatchStrength: Sendable, Hashable {
    /// Named after the app's bundle ID, so it is the app's own.
    case bundleID
    /// Only shares the app's name, so it could belong to something else.
    case name
}

/// What a related file is, in the words shown to the user.
nonisolated enum AppRelatedItemKind: Int, CaseIterable, Sendable, Hashable {
    case appData
    case sandboxData
    case sharedData
    case settings
    case cache
    case webData
    case cookies
    case logs
    case savedState
    case backgroundHelper
    case scripts

    var label: String {
        switch self {
        case .appData, .sandboxData: return "App data"
        case .sharedData: return "Shared app data"
        case .settings: return "Settings"
        case .cache: return "Cache"
        case .webData: return "Web data"
        case .cookies: return "Cookies"
        case .logs: return "Logs"
        case .savedState: return "Saved windows"
        case .backgroundHelper: return "Starts at login"
        case .scripts: return "Scripts"
        }
    }

    var symbolName: String {
        switch self {
        case .appData, .sandboxData, .sharedData: return "folder"
        case .settings: return "gearshape"
        case .cache: return "internaldrive"
        case .webData, .cookies: return "globe"
        case .logs: return "doc.text"
        case .savedState: return "macwindow"
        case .backgroundHelper: return "power"
        case .scripts: return "applescript"
        }
    }

    /// Data the app rebuilds by itself; losing it costs nothing but a slower first launch.
    var isRegenerable: Bool {
        switch self {
        case .cache, .webData, .logs, .savedState: return true
        default: return false
        }
    }
}

/// One file or folder in `~/Library` that belongs to an app.
nonisolated struct AppRelatedItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }

    let url: URL
    let kind: AppRelatedItemKind
    let match: AppMatchStrength
    let sizeBytes: Int64

    /// Name-only matches start unticked: they may be another app's folder.
    var isSelectedByDefault: Bool { match == .bundleID }
}

/// One app and the files found for it, waiting for the user to confirm.
struct AppUninstallReview: Identifiable {
    let id = UUID()
    let app: InstalledApp
    let relatedItems: [AppRelatedItem]
    let context: AppCatalogContext
}

/// Everything else that is installed, so uninstalling one app never takes
/// another app's files. Values are lowercased: bundle IDs and APFS names are
/// compared without case.
nonisolated struct AppCatalogContext: Sendable, Hashable {
    var otherBundleIDs: Set<String>
    var otherFolderNames: Set<String>

    init(otherBundleIDs: Set<String> = [], otherFolderNames: Set<String> = []) {
        self.otherBundleIDs = otherBundleIDs
        self.otherFolderNames = otherFolderNames
    }

    init(apps: [InstalledApp], excluding app: InstalledApp) {
        let others = apps.filter { $0.id != app.id }
        otherBundleIDs = Set(others.map { $0.bundleID.lowercased() })
        otherFolderNames = Set(others.flatMap { $0.folderNames.map { $0.lowercased() } })
    }
}
