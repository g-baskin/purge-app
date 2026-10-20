import Foundation
import Testing
@testable import Purge

@Suite("Personal copy launch lock")
struct PersonalCopyLockTests {
    @Test func onlyCanonicalSignedProductionCopyIsAllowed() {
        #expect(PersonalCopyLock.decision(bundleURL: PersonalCopyLock.canonicalAppURL,
            identifier: PersonalCopyLock.bundleIdentifier, isTesting: false, validSignature: true) == .personalCopy)
    }

    @Test func movedOrCopiedAppIsDeniedEvenWithSameSignature() {
        for path in ["/Applications/Purge.app", "/tmp/Purge.app",
                     "/Users/dellcbyerllc/projects/purge-app/build/check/Build/Products/Debug/Purge.app"] {
            #expect(PersonalCopyLock.decision(bundleURL: URL(fileURLWithPath: path),
                identifier: PersonalCopyLock.bundleIdentifier, isTesting: false, validSignature: true) == .denied)
        }
    }

    @Test func adHocOrWrongCertificateIsDenied() {
        #expect(PersonalCopyLock.decision(bundleURL: PersonalCopyLock.canonicalAppURL,
            identifier: PersonalCopyLock.bundleIdentifier, isTesting: false, validSignature: false) == .denied)
    }

    @Test func testEnvironmentCannotBypassProductionLock() {
        #expect(PersonalCopyLock.decision(bundleURL: URL(fileURLWithPath: "/tmp/Purge.app"),
            identifier: PersonalCopyLock.bundleIdentifier, isTesting: true, validSignature: true) == .denied)
        #expect(PersonalCopyLock.decision(bundleURL: PersonalCopyLock.canonicalAppURL,
            identifier: PersonalCopyLock.bundleIdentifier, isTesting: true, validSignature: false) == .denied)
    }

    @Test func isolatedTestHostIsAllowedOnlyDuringTests() {
        let url = URL(fileURLWithPath: "/tmp/TestHost.app")
        #expect(PersonalCopyLock.decision(bundleURL: url, identifier: PersonalCopyLock.testBundleIdentifier,
            isTesting: true, validSignature: false) == .isolatedTests)
        #expect(PersonalCopyLock.decision(bundleURL: url, identifier: PersonalCopyLock.testBundleIdentifier,
            isTesting: false, validSignature: false) == .denied)
    }

    @Test func unknownIdentifierIsDenied() {
        #expect(PersonalCopyLock.decision(bundleURL: PersonalCopyLock.canonicalAppURL,
            identifier: nil, isTesting: true, validSignature: true) == .denied)
    }

    @Test func isolatedTestProcessDoesNotMatchPersonalSigningRequirement() {
        #expect(!PersonalCopyLock.validCurrentSignature())
    }

    @Test func upstreamCannotReplacePersonalCopy() {
        #expect(!PersonalCopyLock.allowsUpstreamUpdates)
    }

    @Test func testBundleUsesIsolatedIdentity() {
        #expect(Bundle.main.bundleIdentifier == PersonalCopyLock.testBundleIdentifier)
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        #expect(schemes.contains("purge-testhost"))
        #expect(!schemes.contains("purge"))
    }
}
