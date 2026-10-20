import Foundation
import Combine

nonisolated enum DownloadsPolicy {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true) }
    static func isEligible(_ url: URL, root: URL = DownloadsPolicy.root) -> Bool {
        let item = url.standardizedFileURL
        let folder = root.standardizedFileURL
        guard item.path != folder.path, item.deletingLastPathComponent().path == folder.path,
              item.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path,
              let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]),
              values.isSymbolicLink != true else { return false }
        return values.isRegularFile == true || values.isDirectory == true
    }
}

nonisolated struct DownloadEntry: Identifiable, Sendable {
    let url: URL
    let isFolder: Bool
    let modified: Date?
    var sizeBytes: Int64?
    var id: String { url.path }
}

@MainActor final class DownloadsModel: ObservableObject {
    @Published private(set) var items: [DownloadEntry] = []
    @Published private(set) var busy = false
    @Published var selection: Set<String> = []
    @Published var message: String?
    @Published var errorMessage: String?
    init(items: [DownloadEntry] = []) { self.items = items }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            items = try await Task.detached(priority: .utility) {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
                let children = try FileManager.default.contentsOfDirectory(at: DownloadsPolicy.root,
                    includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                return children.compactMap { url -> DownloadEntry? in
                    guard DownloadsPolicy.isEligible(url), let values = try? url.resourceValues(forKeys: keys) else { return nil }
                    return DownloadEntry(url: url, isFolder: values.isDirectory == true,
                        modified: values.contentModificationDate,
                        sizeBytes: values.isDirectory == true ? nil : values.fileSize.map(Int64.init))
                }.sorted { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
            }.value
            selection.formIntersection(Set(items.map(\.id)))
        } catch { items = []; selection = []; errorMessage = "Downloads could not be read. Check Purge’s Full Disk Access, then refresh." }
    }

    func measure(_ item: DownloadEntry) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let size = await Task.detached(priority: .utility) { FolderSizing.directoryByteSize(at: item.url) }.value
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].sizeBytes = size }
    }

    func trashSelection(_ confirmedIDs: Set<String>? = nil) async {
        guard !busy else { return }
        let chosen = items.filter { (confirmedIDs ?? selection).contains($0.id) }
        guard !chosen.isEmpty else { return }
        busy = true
        do {
            var sizes: [String: Int64] = [:]
            for item in chosen {
                guard DownloadsPolicy.isEligible(item.url) else { continue }
                if let size = item.sizeBytes { sizes[item.id] = size }
                else { sizes[item.id] = await Task.detached(priority: .utility) { FolderSizing.directoryByteSize(at: item.url) }.value }
            }
            let report = try await FileDeleter().deleteUserSelectedFiles(at: chosen.map(\.url), pathToExpectedSizeBytes: sizes)
            let left = report.failedItems.count + report.skippedItems.count
            message = "Moved \(report.deletedItems.count) item(s) to Trash. \(left) left unchanged. Nothing was permanently deleted."
            selection = []
        } catch { errorMessage = error.localizedDescription }
        busy = false
        await refresh()
    }
}
