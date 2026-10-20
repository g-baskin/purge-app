import Foundation
import Testing

@Suite("Bundled license notices")
struct BundledLicenseTests {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceNotice(_ name: String) throws -> String {
        try String(
            contentsOf: sourceRoot.appendingPathComponent("purge/Resources/Legal/\(name)-LICENSE.txt"),
            encoding: .utf8
        )
    }

    @Test(arguments: ["Purge", "Sparkle"])
    func bundledNoticesMatchCompleteSourceCopies(_ name: String) throws {
        let url = try #require(
            Bundle.main.url(forResource: "\(name)-LICENSE", withExtension: "txt", subdirectory: "Legal")
                ?? Bundle.main.url(forResource: "\(name)-LICENSE", withExtension: "txt")
        )
        let bundled = try String(contentsOf: url, encoding: .utf8)
        let source = try sourceNotice(name)
        #expect(bundled == source)
    }

    @Test
    func projectNoticeMatchesRootLicense() throws {
        let rootLicense = try String(contentsOf: sourceRoot.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(try sourceNotice("Purge") == rootLicense)
    }

    @Test
    func sparkleNoticeRetainsThirdPartyNotices() throws {
        let notice = try sourceNotice("Sparkle")
        for required in [
            "Copyright (c) 2006-2013 Andy Matuschak.",
            "EXTERNAL LICENSES",
            "bspatch.c and bsdiff.c",
            "Copyright 2003-2005 Colin Percival",
            "sais.c and sais.h",
            "Copyright (c) 2008-2010 Yuta Mori",
            "Portable C implementation of Ed25519",
            "Copyright (c) 2015 Orson Peters",
            "SUSignatureVerifier.m:",
            "Copyright (c) 2011 Mark Hamlin.",
            "Permission is hereby granted, free of charge",
            "documentation and/or other materials provided with the distribution.",
        ] {
            #expect(notice.contains(required), "Missing license notice: \(required)")
        }
    }
}
