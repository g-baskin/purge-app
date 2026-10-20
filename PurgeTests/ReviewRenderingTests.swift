import AppKit
import SwiftUI
import Testing
@testable import Purge

@Suite("Native review view rendering")
@MainActor
struct ReviewRenderingTests {
    private func capture<V: View>(_ name: String, _ view: V, folder: URL, dark: Bool) async throws {
        let content = view.frame(width: 860, height: 850)
            .environment(\.colorScheme, dark ? .dark : .light)
        // ImageRenderer cannot draw native scroll views, text fields or pickers.
        // Host the real controls in an offscreen window instead; no screen-capture permission is needed.
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 860, height: 850),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        // Yield the main actor while AppKit renders, so concurrent queue tests can progress.
        try await Task.sleep(for: .milliseconds(150))
        hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent(name + (dark ? "-dark.png" : "-light.png")))
    }

    @Test func newViewsRenderInBothAppearancesWithoutRealDockerOrAuthentication() async throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/personal-copy-ui-proof/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = DeletionProtection(fileURL: nil)
        let file = URL(fileURLWithPath: "/tmp/Important app.app")
        try store.protect(url: file)
        let protections = ProtectionModel(store: store)
        let fixture = try JSONSerialization.data(withJSONObject: [
            "Images": [["Id": "sha256:" + String(repeating: "a", count: 64), "RepoTags": ["postgres:16"], "Size": 350000000, "Containers": 0]],
            "Containers": [["Id": String(repeating: "b", count: 64), "Names": ["/running-database"], "State": "running", "SizeRw": 20000000]],
            "Volumes": [["Name": "database-data", "CreatedAt": "2026-10-19T10:00:00Z", "UsageData": ["Size": 8000000000, "RefCount": 0]]],
            "BuildCache": [["ID": "cache-fixture", "Description": "Build layers", "Size": 1200000000]]
        ])
        let client = DockerClient(protections: store, request: { _, path in
            path == "/info" ? Data("{\"ID\":\"render-fixture\"}".utf8) : fixture
        })
        let docker = DockerModel(client: client)
        await docker.refresh()
        #expect(docker.snapshot?.resources.count == 4)
        let offline = DockerModel(client: DockerClient(protections: store, request: { _, _ in throw DockerError.offline }))
        await offline.refresh()
        #expect(offline.snapshot == nil)
        let downloads = DownloadsModel(items: [
            DownloadEntry(url: URL(fileURLWithPath: "/tmp/Downloads/Install.dmg"), isFolder: false,
                modified: Date(timeIntervalSince1970: 1_790_000_000), sizeBytes: 3200000000),
            DownloadEntry(url: URL(fileURLWithPath: "/tmp/Downloads/Project archive.zip"), isFolder: false,
                modified: Date(timeIntervalSince1970: 1_790_000_000), sizeBytes: 800000000),
            DownloadEntry(url: URL(fileURLWithPath: "/tmp/Downloads/Project folder"), isFolder: true, modified: nil, sizeBytes: nil)
        ])
        for dark in [false, true] {
            try await capture("docker-fixture", DockerView(model: docker, protections: protections), folder: folder, dark: dark)
            try await capture("docker-offline", DockerView(model: offline, protections: protections), folder: folder, dark: dark)
            try await capture("downloads-fixture", DownloadsView(model: downloads, protections: protections), folder: folder, dark: dark)
            try await capture("protection-fixture", ProtectionSettingsSection(model: protections), folder: folder, dark: dark)
        }
        print("Native UI fixture captures: \(folder.path)")
    }
}
