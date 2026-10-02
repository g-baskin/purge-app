import CoreServices
import Foundation
import Testing
@testable import Purge

/// A stand-in for the FSEvents journal: changes are recorded with increasing ids,
/// and a replay returns the ones under the watched folders after a position.
private final class FakeJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var eventID: UInt64 = 1_000
    private var changes: [(id: UInt64, path: String, lost: Bool)] = []
    var uuid = "journal-A"
    var available = true
    /// Returned by `eventIDBefore`, standing in for "the position N hours ago".
    var replayCutoff: UInt64 = 0
    private(set) var replayCount = 0
    var replayDelay: TimeInterval = 0

    func change(_ path: String, lost: Bool = false) {
        lock.lock()
        eventID += 1
        changes.append((eventID, path, lost))
        lock.unlock()
    }

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return eventID
    }

    var journal: FolderSizeCache.Journal {
        FolderSizeCache.Journal(
            currentEventID: { [unowned self] in self.current },
            uuid: { [unowned self] in self.uuid },
            eventIDBefore: { [unowned self] _ in self.replayCutoff },
            replay: { [unowned self] roots, since, _ in
                if self.replayDelay > 0 { Thread.sleep(forTimeInterval: self.replayDelay) }
                self.lock.lock()
                defer { self.lock.unlock() }
                self.replayCount += 1
                guard self.available else { return .unavailable }
                let relevant = self.changes.filter { change in
                    change.id > since && roots.contains { FolderSizeCache.isSameOrRelated(change.path, $0) }
                }
                return .changes(
                    changedPaths: relevant.filter { !$0.lost }.map { $0.path + "/" },
                    lostRoots: relevant.filter(\.lost).map(\.path),
                    eventCount: relevant.count
                )
            }
        )
    }
}

/// Folder identities and the clock, both under the test's control.
private final class FakeDisk: @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [String: FolderSizeCache.Identity] = [:]
    private var nextInode: UInt64 = 100
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func add(_ path: String) {
        lock.lock()
        nextInode += 1
        identities[path] = .init(device: 1, inode: nextInode, changeTime: 1)
        lock.unlock()
    }

    func remove(_ path: String) {
        lock.lock()
        identities[path] = nil
        lock.unlock()
    }

    func touch(_ path: String) {
        lock.lock()
        identities[path]?.changeTime += 1
        lock.unlock()
    }

    func identity(_ path: String) -> FolderSizeCache.Identity? {
        lock.lock()
        defer { lock.unlock() }
        return identities[path]
    }
}

/// Counts what each call actually walked.
private final class Measurer: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var walked: [[String]] = []
    var sizes: [String: Int64] = [:]
    var onMeasure: (() -> Void)?

    func measure(_ urls: [URL]) -> [String: Int64] {
        onMeasure?()
        let keys = urls.map { $0.standardizedFileURL.path }
        lock.lock()
        defer { lock.unlock() }
        walked.append(keys)
        var result: [String: Int64] = [:]
        for key in keys {
            if let bytes = sizes[key] { result[key] = bytes }
        }
        return result
    }

    var lastWalked: [String] {
        lock.lock()
        defer { lock.unlock() }
        return walked.last ?? []
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return walked.count
    }
}

private struct Rig {
    let journal = FakeJournal()
    let disk = FakeDisk()
    let measurer = Measurer()
    var fullDiskAccess = true
    var fileURL: URL?

    init(folders: [String: Int64], fileURL: URL? = nil) {
        self.fileURL = fileURL
        for (path, bytes) in folders {
            disk.add(path)
            measurer.sizes[path] = bytes
        }
    }

    func makeCache() -> FolderSizeCache {
        let disk = self.disk
        let access = fullDiskAccess
        return FolderSizeCache(
            fileURL: fileURL,
            journal: journal.journal,
            hasFullDiskAccess: { access },
            identity: { disk.identity($0) },
            now: { disk.now }
        )
    }

    func sizes(_ cache: FolderSizeCache, _ paths: [String]) -> [String: Int64] {
        cache.sizes(for: paths.map { URL(fileURLWithPath: $0) }) { measurer.measure($0) }
    }
}

@Suite("Folder size cache")
struct FolderSizeCacheTests {
    let a = "/Users/test/Library/Caches/com.example.a"
    let b = "/Users/test/Library/Caches/com.example.b"

    @Test("Unchanged folders are reused without a walk")
    func reusesUnchangedFolders() {
        let rig = Rig(folders: [a: 100, b: 200])
        let cache = rig.makeCache()

        #expect(rig.sizes(cache, [a, b]) == [a: 100, b: 200])
        #expect(Set(rig.measurer.lastWalked) == [a, b])

        rig.disk.now += 60
        #expect(rig.sizes(cache, [a, b]) == [a: 100, b: 200])
        #expect(rig.measurer.callCount == 1, "the second scan walked again")
    }

    @Test("A change anywhere inside a folder measures it again")
    func remeasuresAfterAChangeInside() {
        let rig = Rig(folders: [a: 100, b: 200])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a, b])

        rig.journal.change(a + "/deep/er")
        rig.measurer.sizes[a] = 150
        rig.disk.now += 60

        #expect(rig.sizes(cache, [a, b]) == [a: 150, b: 200])
        #expect(rig.measurer.lastWalked == [a])
    }

    @Test("A change in the parent folder alone keeps the size")
    func parentChangeKeepsTheSize() {
        let rig = Rig(folders: [a: 100])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a])

        rig.journal.change("/Users/test/Library/Caches")
        rig.disk.now += 60

        #expect(rig.sizes(cache, [a]) == [a: 100])
        #expect(rig.measurer.callCount == 1)
    }

    @Test("A folder replaced, moved back, or removed is measured again")
    func identityChangesMeasureAgain() {
        let rig = Rig(folders: [a: 100, b: 200])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a, b])

        rig.disk.add(a) // replaced: new inode
        rig.disk.touch(b) // moved away and back: new change time
        rig.journal.change("/Users/test/Library/Caches")
        rig.disk.now += 60

        _ = rig.sizes(cache, [a, b])
        #expect(Set(rig.measurer.lastWalked) == [a, b])
    }

    @Test("Lost journal events measure everything under that folder again")
    func lostEventsMeasureAgain() {
        let rig = Rig(folders: [a: 100, b: 200])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a, b])

        rig.journal.change(b, lost: true)
        rig.disk.now += 60

        _ = rig.sizes(cache, [a, b])
        #expect(rig.measurer.lastWalked == [b])
    }

    @Test("When the journal can't vouch for the gap, everything is measured")
    func unavailableJournalMeasuresAll() {
        let rig = Rig(folders: [a: 100, b: 200])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a, b])

        rig.journal.available = false
        rig.journal.change(a)
        rig.disk.now += 60

        _ = rig.sizes(cache, [a, b])
        #expect(Set(rig.measurer.lastWalked) == [a, b])
    }

    @Test("Without Full Disk Access nothing is cached")
    func noAccessMeasuresEveryTime() {
        var rig = Rig(folders: [a: 100])
        rig.fullDiskAccess = false
        let cache = rig.makeCache()

        _ = rig.sizes(cache, [a])
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 2)
        #expect(cache.entryCount == 0)
    }

    @Test("A change during the walk is caught by the next check")
    func changeDuringWalkIsCaught() {
        let rig = Rig(folders: [a: 100])
        let cache = rig.makeCache()
        rig.measurer.onMeasure = { rig.journal.change(a + "/during") }
        _ = rig.sizes(cache, [a])
        rig.measurer.onMeasure = nil

        rig.disk.now += 60
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 2, "a change made while measuring was covered up")
    }

    @Test("A folder that couldn't be measured isn't saved")
    func failedMeasurementIsNotSaved() {
        let rig = Rig(folders: [a: 100])
        rig.measurer.sizes[b] = nil
        rig.disk.add(b)
        let cache = rig.makeCache()

        #expect(rig.sizes(cache, [a, b]) == [a: 100])
        rig.disk.now += 60
        _ = rig.sizes(cache, [a, b])
        #expect(rig.measurer.lastWalked == [b])
    }

    @Test("A folder the journal can't follow is never saved")
    func unfollowableFolderIsNotSaved() {
        let rig = Rig(folders: [a: 100])
        rig.disk.remove(a) // a symlink, another disk, or a spelling the journal doesn't use
        let cache = rig.makeCache()

        _ = rig.sizes(cache, [a])
        rig.disk.now += 60
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 2)
    }

    @Test("Purge's own changes forget the folder, what's inside, and what holds it")
    func invalidateForgetsRelatedFolders() {
        let parent = "/Users/test/Library/Caches"
        let inside = a + "/inner"
        let rig = Rig(folders: [parent: 1_000, a: 100, inside: 10, b: 200])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [parent, a, inside, b])

        cache.invalidate([URL(fileURLWithPath: a)])
        rig.disk.now += 60

        _ = rig.sizes(cache, [parent, a, inside, b])
        #expect(Set(rig.measurer.lastWalked) == [parent, a, inside])
    }

    @Test("Sizes are measured again after about a day, changes or not")
    func expiredSizesAreMeasuredAgain() {
        let rig = Rig(folders: [a: 100])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a])

        rig.disk.now += 17 * 60 * 60 // under the shortest limit
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 1)

        rig.disk.now += 14 * 60 * 60 // past the longest limit
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 2)
    }

    @Test("Sizes last checked too long ago are measured, not replayed")
    func tooOldToReplayIsMeasured() {
        let rig = Rig(folders: [a: 100])
        let cache = rig.makeCache()
        _ = rig.sizes(cache, [a])

        rig.journal.change("/elsewhere") // moves the journal on
        rig.journal.replayCutoff = rig.journal.current
        rig.disk.now += 60
        _ = rig.sizes(cache, [a])
        #expect(rig.measurer.callCount == 2)
    }

    @Test("Saved sizes survive a relaunch, but not a new journal or a damaged file")
    func persistence() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folder-size-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let rig = Rig(folders: [a: 100], fileURL: file)
        let first = rig.makeCache()
        _ = rig.sizes(first, [a])
        first.save()

        // Relaunch: a new cache reads the file and reuses the size.
        rig.disk.now += 60
        #expect(rig.sizes(rig.makeCache(), [a]) == [a: 100])
        #expect(rig.measurer.callCount == 1)

        // A different journal (reset, or another Mac's disk): discarded.
        rig.journal.uuid = "journal-B"
        _ = rig.sizes(rig.makeCache(), [a])
        #expect(rig.measurer.callCount == 2)

        // A damaged file: ignored, and measured again.
        try Data("not json".utf8).write(to: file)
        _ = rig.sizes(rig.makeCache(), [a])
        #expect(rig.measurer.callCount == 3)
    }

    @Test("Many scans at once share one journal check and all finish", .timeLimit(.minutes(1)))
    func concurrentScansShareOneCheck() async {
        let paths = (0..<40).map { "/Users/test/Library/Caches/folder-\($0)" }
        let rig = Rig(folders: Dictionary(uniqueKeysWithValues: paths.map { ($0, Int64(10)) }))
        let cache = rig.makeCache()
        _ = rig.sizes(cache, paths)
        rig.journal.change(paths[0] + "/x")
        rig.journal.replayDelay = 0.3
        rig.disk.now += 60

        let callers = ProcessInfo.processInfo.activeProcessorCount * 2
        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<callers {
                group.addTask { rig.sizes(cache, paths).count }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(results.count == callers)
        #expect(results.allSatisfy { $0 == paths.count })
        #expect(rig.journal.replayCount <= 2, "replayed \(rig.journal.replayCount) times for one burst")
    }

    @Test("Watched folders are the fewest that cover every saved folder")
    func watchRootsCoverAll() {
        #expect(FolderSizeCache.watchRoots(for: ["/a/b", "/a/b/c", "/a/d"]) == ["/a/b", "/a/d"])
        let many = (0..<(FolderSizeCache.maxWatchRoots + 10)).map { "/Users/t/Library/Caches/f\($0)" }
        #expect(FolderSizeCache.watchRoots(for: many) == ["/Users/t/Library/Caches"])
    }
}

/// The real journal and file system, on folders this test makes.
@Suite("Folder size cache on the real disk", .serialized)
struct FolderSizeCacheLiveTests {
    private func makeFolder() throws -> String {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purge-fsc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("inner/deeper"),
            withIntermediateDirectories: true
        )
        // The journal reports real paths, and the temporary folder sits behind the
        // /var symlink. Not `resolvingSymlinksInPath()`: it turns /private/var back
        // into /var on purpose.
        let real = try #require(realpath(base.path, nil))
        defer { free(real) }
        return String(cString: real)
    }

    @Test("The journal reports a change deep inside a folder")
    func journalReportsChangesInside() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        Thread.sleep(forTimeInterval: 1)
        let since = UInt64(FSEventsGetCurrentEventId())
        try Data([1]).write(to: URL(fileURLWithPath: folder + "/inner/deeper/file"))

        var reported: [String] = []
        for _ in 0..<20 where !reported.contains(folder + "/inner/deeper") {
            Thread.sleep(forTimeInterval: 0.25)
            if case let .changes(changed, _, _) = FolderSizeCacheReplay.run(roots: [folder], since: since, isCancelled: { false }) {
                reported = changed.map(FolderSizeCache.normalized)
            }
        }
        #expect(reported.contains(folder + "/inner/deeper"), "reported: \(reported)")
    }

    @Test("Only folders at their real path are trusted, and moving one changes its identity")
    func identityRules() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        #expect(folder.hasPrefix("/private/var/"), "expected the real path, got \(folder)")
        let viaSymlink = folder.replacingOccurrences(of: "/private/var/", with: "/var/")

        let before = try #require(FolderSizeCache.liveIdentity(of: folder))
        #expect(FolderSizeCache.liveIdentity(of: viaSymlink) == nil)
        try Data([1]).write(to: URL(fileURLWithPath: folder + "/file"))
        #expect(FolderSizeCache.liveIdentity(of: folder + "/file") == nil, "a file isn't a folder")

        Thread.sleep(forTimeInterval: 0.05)
        try FileManager.default.moveItem(atPath: folder, toPath: folder + "-away")
        try FileManager.default.moveItem(atPath: folder + "-away", toPath: folder)
        let after = try #require(FolderSizeCache.liveIdentity(of: folder))
        #expect(after.inode == before.inode)
        #expect(after != before, "moving it away and back went unnoticed")
    }
}
