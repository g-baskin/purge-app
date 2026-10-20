import Darwin
import Foundation
import Security

/// This personal fork has one normal launch location and one existing signing identity.
/// Not a macOS-wide application restriction: older/external binaries cannot inherit this guard.
nonisolated enum PersonalCopyLock {
    static let bundleIdentifier = "io.getpurge.app"
    static let testBundleIdentifier = "io.getpurge.app.testhost"
    static let certificateSHA1 = "1FDC8F78848AE0D55DC04F9F854DED710B3AA2D6"
    static let canonicalAppURL = URL(fileURLWithPath:
        "/Users/dellcbyerllc/projects/purge-app/build/dev/Build/Products/Debug/Purge.app",
        isDirectory: true)
    static let allowsUpstreamUpdates = false
    static let requirement = "identifier \"io.getpurge.app\" and certificate leaf = H\"1FDC8F78848AE0D55DC04F9F854DED710B3AA2D6\""

    enum Decision: Equatable {
        case personalCopy
        case isolatedTests
        case denied
    }

    static func decision(bundleURL: URL, identifier: String?, isTesting: Bool, validSignature: Bool) -> Decision {
        if identifier == testBundleIdentifier {
            return isTesting ? .isolatedTests : .denied
        }
        // A test environment variable must NEVER bypass the production path/signature checks.
        guard identifier == bundleIdentifier,
              bundleURL.standardizedFileURL.resolvingSymlinksInPath()
                == canonicalAppURL.standardizedFileURL.resolvingSymlinksInPath(),
              validSignature else { return .denied }
        return .personalCopy
    }

    static func validCurrentSignature() -> Bool {
        var code: SecCode?
        var expected: SecRequirement?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(requirement as CFString, SecCSFlags(), &expected) == errSecSuccess,
              let expected else { return false }
        return SecCodeCheckValidity(code, SecCSFlags(), expected) == errSecSuccess
    }

    /// Called before the app delegate, models, preferences, scanners or updater are created.
    static func enforce() {
        let identifier = Bundle.main.bundleIdentifier
        let testing = TestHost.isActive()
        let result = decision(
            bundleURL: Bundle.main.bundleURL,
            identifier: identifier,
            isTesting: testing,
            validSignature: identifier == bundleIdentifier && validCurrentSignature()
        )
        guard result != .denied else {
            fputs("This Purge copy cannot run. Open the signed personal copy using scripts/open-my-purge.sh in /Users/dellcbyerllc/projects/purge-app.\n", stderr)
            exit(78)
        }
    }
}
