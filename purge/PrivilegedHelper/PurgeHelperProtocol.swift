import Foundation

/// The single source of truth for the identifiers and code-signing requirements the
/// app and the privileged helper use to find and vouch for each other. Both targets
/// compile this file, so the two ends can never drift apart on a name or a
/// requirement string — a drift that would surface only as a silent XPC failure.
enum PurgeHelperConstants {
    /// launchd label, Mach service name, and helper bundle identifier — all one string.
    static let machServiceName = "io.getpurge.helper"

    /// The helper's build version, shared so the app and the daemon agree on it.
    /// Bump it whenever the helper's behaviour changes: the app compares this against
    /// the version a running helper reports and re-registers when an older copy
    /// survived an update.
    ///
    /// v3 adds the administrator-only caller gate and the ownership-reporting move, so
    /// an app that talks the v3 protocol re-registers any surviving v2 helper first.
    static let version = "3"

    /// The daemon property list bundled at `Contents/Library/LaunchDaemons/`, named
    /// to `SMAppService.daemon(plistName:)`.
    static let daemonPlistName = "io.getpurge.helper.plist"

    /// The team the app and helper are both signed by. Baked into the requirements
    /// below so a differently-signed binary can neither impersonate the app to the
    /// helper nor the helper to the app.
    static let teamIdentifier = "BX83ZBV95B"

    /// What the helper demands of whoever connects: the genuine, Apple-notarized,
    /// same-team Purge app. Applied with `NSXPCConnection.setCodeSigningRequirement`.
    /// A local build may also be accepted; see ``localSigningCertificateKey``.
    static var clientRequirement: String {
        requirement(identifier: "io.getpurge.app", localCertificateSHA1: bundledLocalCertificateSHA1())
    }

    /// What the app demands of the helper it dials, so a planted binary answering on
    /// the same Mach service cannot pose as the helper.
    static var helperRequirement: String {
        requirement(identifier: machServiceName, localCertificateSHA1: bundledLocalCertificateSHA1())
    }

    /// Info.plist key holding the SHA-1 fingerprint of the private certificate a
    /// local build is signed with (`scripts/dev-sign.sh` writes it). With it, both
    /// ends also accept code signed by that one certificate, so a build signed
    /// without an Apple developer account can use the helper. Release builds never
    /// carry the key and keep the team-only requirement.
    ///
    /// The key is read from the reader's own bundle, which its signature seals: a
    /// changed value breaks the signature, and macOS won't run it. The helper reads
    /// the app bundle it was registered from (two levels above its executable), so a
    /// file placed elsewhere can't change what it trusts.
    static let localSigningCertificateKey = "PurgeLocalSigningCertificateSHA1"

    /// The requirement for `identifier`: the official team always, plus one local
    /// certificate when a valid fingerprint is given.
    static func requirement(identifier: String, localCertificateSHA1: String?) -> String {
        let official =
            "identifier \"\(identifier)\" and anchor apple generic and " +
            "certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        guard let fingerprint = localCertificateSHA1.flatMap(validatedFingerprint) else {
            return official
        }
        return "(\(official)) or (identifier \"\(identifier)\" and certificate leaf = H\"\(fingerprint)\")"
    }

    /// Exactly 40 hex digits, lowercased; anything else is ignored, so a bad value
    /// can never widen the requirement or break its syntax.
    static func validatedFingerprint(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.utf8.count == 40,
              trimmed.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) })
        else { return nil }
        return trimmed
    }

    /// The local certificate fingerprint from Purge.app's Info.plist, for both the
    /// app and the helper inside it. `nil` in releases.
    static func bundledLocalCertificateSHA1() -> String? {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        // The app's executable and the helper both sit in Purge.app/Contents/MacOS.
        let infoPlist = executable.resolvingSymlinksInPath()
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Info.plist")
        return localCertificateSHA1(infoPlist: infoPlist)
    }

    /// The fingerprint in one Purge.app Info.plist, or `nil` when it has none (every
    /// release), belongs to another app, or holds anything but a valid fingerprint.
    static func localCertificateSHA1(infoPlist: URL) -> String? {
        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == "io.getpurge.app",
              let value = plist[localSigningCertificateKey] as? String
        else { return nil }
        return validatedFingerprint(value)
    }

    /// Directories whose immediate children the uninstaller may offer as leftovers.
    /// Keep this in the shared file so the root helper enforces the same boundary as
    /// the scanner instead of trusting paths supplied over XPC.
    private static let userLeftoverRelativeRoots = [
        "Library/Application Support",
        "Library/Caches",
        "Library/HTTPStorages",
        "Library/Preferences",
        "Library/Containers",
        "Library/Group Containers",
        "Library/Saved Application State",
        "Library/Logs",
        "Library/LaunchAgents"
    ]

    private static let systemLeftoverRoots = [
        "/Library/LaunchDaemons",
        "/Library/Application Support",
        "/Library/LaunchAgents"
    ]

    /// Returns true only for locations the app-uninstall scanner can produce:
    /// an app bundle in an Applications folder, or one direct child of a known
    /// leftover directory. Symlinks are rejected so an allowed-looking path cannot
    /// redirect the root helper somewhere else between path components.
    static func isAllowedUninstallLocation(_ url: URL, homeDirectory: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.path == resolved.path else { return false }

        let home = homeDirectory.standardizedFileURL
        let userRoots = userLeftoverRelativeRoots.map {
            home.appendingPathComponent($0, isDirectory: true).standardizedFileURL
        }
        let machineRoots = systemLeftoverRoots.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        let parent = standardized.deletingLastPathComponent().path
        if (userRoots + machineRoots).contains(where: { $0.path == parent }) {
            return true
        }

        let appRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        guard standardized.pathExtension.lowercased() == "app" else { return false }
        let appParent = standardized.deletingLastPathComponent()
        if appRoots.contains(where: { appParent.path == $0.path }) { return true }

        let grandparent = appParent.deletingLastPathComponent()
        return appRoots.contains { grandparent.path == $0.path }
    }
}

/// The privileged operations the helper exposes over XPC. Deliberately tiny: the
/// helper runs as root, so every method here is attack surface. It does exactly one
/// thing — move already-chosen paths into a Trash directory and hand ownership back
/// to the user — and nothing that could be turned into an arbitrary-write primitive.
@objc(PurgeHelperProtocol) protocol PurgeHelperProtocol {
    /// Moves each path in `paths` into the connecting user's Trash as root, then hands
    /// ownership back to that same user so they can empty the Trash unaided.
    /// Replies with the subset of `paths` that are now gone from their source.
    ///
    /// Kept for wire compatibility with a v2 app talking to a v3 helper. New callers
    /// use `moveToTrashReportingOwnership`, which also names the items whose ownership
    /// could not be fully handed back.
    func moveToTrash(
        paths: [String],
        withReply reply: @escaping (_ movedPaths: [String]) -> Void
    )

    /// Same move as `moveToTrash`, but the reply also names the subset of moved items
    /// whose ownership could not be fully handed back to the user. Those items really
    /// did move to the Trash, but emptying them may prompt for a password, so the app
    /// can say so honestly instead of reporting a clean success.
    func moveToTrashReportingOwnership(
        paths: [String],
        withReply reply: @escaping (_ movedPaths: [String], _ ownershipIncompletePaths: [String]) -> Void
    )

    /// Round-trips the helper's build version so the app can tell whether an older
    /// helper is still installed after an update and re-register if so.
    func helperVersion(withReply reply: @escaping (_ version: String) -> Void)
}
