import Foundation
import Security
import Testing
@testable import Purge

/// The helper runs as root, so who it talks to must stay exactly as narrow as
/// intended: the official team, plus at most one local certificate a local build
/// names in its own signed Info.plist. Releases must never trust anything else.
@Suite("Privileged helper code-signing requirements")
struct PrivilegedHelperRequirementTests {
    private let fingerprint = "1fdc8f78848ae0d55dc04f9f854ded710b3aa2d6"

    private static let officialApp =
        "identifier \"io.getpurge.app\" and anchor apple generic and certificate leaf[subject.OU] = \"BX83ZBV95B\""
    private static let officialHelper =
        "identifier \"io.getpurge.helper\" and anchor apple generic and certificate leaf[subject.OU] = \"BX83ZBV95B\""

    private func compiles(_ text: String) -> Bool {
        var requirement: SecRequirement?
        return SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess
            && requirement != nil
    }

    /// Writes an Info.plist like a built Purge.app's and returns its URL.
    private func infoPlist(_ entries: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurgeHelperRequirement-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private func releaseInfo() -> [String: Any] {
        ["CFBundleIdentifier": "io.getpurge.app", "CFBundleShortVersionString": "1.7.0", "CFBundleVersion": "26"]
    }

    @Test("A release Info.plist (no fingerprint) yields exactly the official requirements")
    func releaseBuildKeepsTheOfficialRequirement() throws {
        let url = try infoPlist(releaseInfo())
        defer { try? FileManager.default.removeItem(at: url) }

        let fingerprint = PurgeHelperConstants.localCertificateSHA1(infoPlist: url)
        #expect(fingerprint == nil)

        let app = PurgeHelperConstants.requirement(identifier: "io.getpurge.app", localCertificateSHA1: fingerprint)
        let helper = PurgeHelperConstants.requirement(identifier: "io.getpurge.helper", localCertificateSHA1: fingerprint)
        #expect(app == Self.officialApp)
        #expect(helper == Self.officialHelper)
        #expect(!app.contains(" or ") && !helper.contains(" or "))
        #expect(!app.contains("certificate leaf = H") && !helper.contains("certificate leaf = H"))
        #expect(compiles(app) && compiles(helper))
    }

    @Test("A local build's Info.plist adds its one certificate")
    func localBuildAddsItsCertificate() throws {
        var info = releaseInfo()
        info[PurgeHelperConstants.localSigningCertificateKey] = fingerprint.uppercased()
        let url = try infoPlist(info)
        defer { try? FileManager.default.removeItem(at: url) }

        let found = PurgeHelperConstants.localCertificateSHA1(infoPlist: url)
        #expect(found == fingerprint)
        let helper = PurgeHelperConstants.requirement(identifier: "io.getpurge.helper", localCertificateSHA1: found)
        #expect(helper == "(\(Self.officialHelper)) or (identifier \"io.getpurge.helper\" and certificate leaf = H\"\(fingerprint)\")")
        #expect(compiles(helper))
    }

    @Test("A fingerprint in another app's Info.plist is ignored")
    func otherAppsPlistIsIgnored() throws {
        let url = try infoPlist([
            "CFBundleIdentifier": "com.example.other",
            PurgeHelperConstants.localSigningCertificateKey: fingerprint,
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PurgeHelperConstants.localCertificateSHA1(infoPlist: url) == nil)
    }

    @Test("A missing or unreadable Info.plist yields no fingerprint")
    func missingPlistIsIgnored() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).plist")
        #expect(PurgeHelperConstants.localCertificateSHA1(infoPlist: missing) == nil)

        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).plist")
        try Data("not a plist".utf8).write(to: garbage)
        defer { try? FileManager.default.removeItem(at: garbage) }
        #expect(PurgeHelperConstants.localCertificateSHA1(infoPlist: garbage) == nil)
    }

    @Test("Malformed fingerprints are ignored, never spliced in", arguments: [
        "", "1fdc8f78", String(repeating: "g", count: 40), "1fdc8f78848ae0d55dc04f9f854ded710b3aa2d6aa",
        "1fdc8f78848ae0d55dc04f9f854ded710b3aa2d\"", "1fdc8f78848ae0d55dc04f9f854ded710b3aa2d6\") or (true",
    ])
    func malformedFingerprintIsIgnored(_ value: String) throws {
        #expect(PurgeHelperConstants.requirement(identifier: "io.getpurge.app", localCertificateSHA1: value) == Self.officialApp)

        var info = releaseInfo()
        info[PurgeHelperConstants.localSigningCertificateKey] = value
        let url = try infoPlist(info)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PurgeHelperConstants.localCertificateSHA1(infoPlist: url) == nil)
    }
}
