import CoreServices
import Foundation

/// Remembers folder sizes between scans and launches, and measures a folder again
/// only when macOS reports that something inside it changed.
///
/// macOS keeps a running record of file system changes, the FSEvents journal. Each
/// saved size carries a journal position it is known to be good through. Before
/// scans reuse sizes, the cache replays the journal from that position, forgets
/// every size a change could touch, and lets the scan walk only those folders.
///
/// Fails toward measuring. A folder is walked again whenever the journal can't
/// vouch for it: the journal was reset or lost events, the replay was slow, the
/// last check is too old, the folder was replaced, or it lives somewhere the
/// journal reports under a different path (a symlink, another disk). Without Full
/// Disk Access the cache is skipped entirely, since macOS may hide changes in
/// folders Purge can't read.
nonisolated final class FolderSizeCache: @unchecked Sendable {
    /// Bump to discard caches written in an older format.
    static let formatVersion = 1
    /// Past this many saved folders something is wrong; the cache starts over.
    static let maxEntries = 50_000
    /// Sizes not checked for this long are measured again rather than checked. A
    /// day of changes can take minutes to replay, longer than measuring. Six hours
    /// replayed in about 6 seconds on an 8-core Mac.
    static let maxReplayAge: TimeInterval = 8 * 60 * 60
    /// Every size is measured again about once a day, even when the journal saw no
    /// change. The journal can't see everything: a file an app keeps open and keeps
    /// writing (a log, a database) is only reported once it's closed. Spread between
    /// 18 and 30 hours per folder, so they don't all expire in the same scan.
    static let maxEntryAge: TimeInterval = 24 * 60 * 60
    /// The longest a scan waits for the journal before measuring instead.
    static let replayTimeout: TimeInterval = 20
    /// Calls this close together share one check of the journal: one scan makes
    /// many calls a second, and its sizes are as of when it started anyway.
    static let recheckInterval: TimeInterval = 2
    /// More folders than this are watched through their shared parents.
    static let maxWatchRoots = 256
    /// Past this many changed folders in one replay, everything counts as changed.
    static let maxChangedPaths = 100_000

    /// The cache scans use. Off in the test host, so tests always measure for real.
    static let shared: FolderSizeCache = {
        if TestHost.isActive() { return FolderSizeCache(fileURL: nil, isEnabled: false) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("io.getpurge.app", isDirectory: true)
        return FolderSizeCache(fileURL: base?.appendingPathComponent("folder-size-cache.json"))
    }()

    struct Entry: Codable, Equatable, Sendable {
        var bytes: Int64
        /// Journal position this size is known to be good through.
        var verifiedThrough: UInt64
        var measuredAt: Date
        /// The folder itself when measured. See ``Identity``.
        var identity: Identity
    }

    /// A folder's identity. Changes that the journal reports only on the parent
    /// folder change this instead: replacing the folder or recreating it gives a new
    /// inode, and moving it away and back again updates its change time.
    struct Identity: Codable, Equatable, Sendable {
        var device: UInt64
        var inode: UInt64
        /// Status change time (`st_ctime`), in nanoseconds.
        var changeTime: Int64
    }

    /// What a replay of the journal found.
    enum Replay: Sendable {
        /// Folders whose contents changed, and watched folders where events were lost.
        case changes(changedPaths: [String], lostRoots: [String], eventCount: Int)
        /// The journal can't vouch for this period (reset, wrapped, too slow).
        case unavailable
        /// The scan was cancelled before the replay finished.
        case cancelled
    }

    /// Access to the FSEvents journal, replaceable in tests.
    struct Journal: Sendable {
        var currentEventID: @Sendable () -> UInt64
        /// Identifies this disk's journal; a new one means every saved position is meaningless.
        var uuid: @Sendable () -> String?
        /// The last journal position before `date`.
        var eventIDBefore: @Sendable (_ date: Date) -> UInt64
        var replay: @Sendable (_ roots: [String], _ since: UInt64, _ isCancelled: @Sendable () -> Bool) -> Replay
    }

    private struct File: Codable {
        var formatVersion: Int
        var journalUUID: String
        var entries: [String: Entry]
    }

    private let fileURL: URL?
    private let isEnabled: Bool
    private let journal: Journal
    private let hasFullDiskAccess: @Sendable () -> Bool
    private let identity: @Sendable (_ path: String) -> Identity?
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private var dirty = false
    private var saveScheduled = false
    private var lastCheck: (eventID: UInt64, at: Date)?
    private var lastSavedAt: ContinuousClock.Instant?
    private var accessCheck: (granted: Bool, at: ContinuousClock.Instant)?
    /// One journal check at a time; others wait and share its result.
    private let checkGate = DispatchSemaphore(value: 1)
    /// Private queues, never GCD's shared pool, so blocked scan threads can't starve them.
    private let saveQueue = DispatchQueue(label: "io.getpurge.folder-size-cache.save")

    init(
        fileURL: URL?,
        isEnabled: Bool = true,
        journal: Journal = .live,
        hasFullDiskAccess: @escaping @Sendable () -> Bool = { PermissionChecker().hasFullDiskAccess() },
        identity: @escaping @Sendable (_ path: String) -> Identity? = { FolderSizeCache.liveIdentity(of: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.journal = journal
        self.hasFullDiskAccess = hasFullDiskAccess
        self.identity = identity
        self.now = now
    }

    // MARK: - Use from scans

    /// Sizes for `urls`: saved ones where nothing changed, `measure`d ones for the
    /// rest. `measure` only receives the folders that need a walk.
    func sizes(for urls: [URL], measure: ([URL]) -> [String: Int64]) -> [String: Int64] {
        guard isEnabled, !urls.isEmpty, fullDiskAccessGranted() else { return measure(urls) }
        loadIfNeeded()
        let validFrom = checkJournal()

        var result: [String: Int64] = [:]
        var missing: [URL] = []
        let currentTime = now()
        lock.lock()
        for url in urls {
            let key = url.standardizedFileURL.path
            if let validFrom, let entry = entries[key], entry.verifiedThrough >= validFrom,
               !Self.isExpired(entry, path: key, at: currentTime) {
                result[key] = entry.bytes
            } else {
                missing.append(url)
            }
        }
        lock.unlock()
        guard !missing.isEmpty else { return result }

        // Both taken before measuring, so anything that changes during the walk
        // shows up at the next check instead of being covered by this measurement.
        let watermark = journal.currentEventID()
        // Only folders the journal reports under this exact path can be trusted.
        var identities: [String: Identity] = [:]
        for url in missing {
            let key = url.standardizedFileURL.path
            identities[key] = identity(key)
        }
        let measured = measure(missing)
        let measuredAt = now()
        var fresh: [String: Entry] = [:]
        for url in missing {
            let key = url.standardizedFileURL.path
            guard let bytes = measured[key] else { continue } // not measured: save nothing
            result[key] = bytes
            guard bytes >= 0, let id = identities[key] else { continue }
            fresh[key] = Entry(bytes: bytes, verifiedThrough: watermark, measuredAt: measuredAt, identity: id)
        }
        if !fresh.isEmpty {
            lock.lock()
            entries.merge(fresh) { _, new in new }
            if entries.count > Self.maxEntries {
                entries.removeAll()
            }
            dirty = true
            lock.unlock()
            scheduleSave()
        }
        return result
    }

    /// Forgets `urls`, everything inside them, and every folder containing them.
    /// For changes Purge makes itself, which the next scan must see at once.
    func invalidate(_ urls: [URL]) {
        guard isEnabled, !urls.isEmpty else { return }
        loadIfNeeded()
        let keys = Set(urls.map { $0.standardizedFileURL.path })
        lock.lock()
        let before = entries.count
        for key in keys {
            entries.removeValue(forKey: key)
            for ancestor in Self.ancestors(of: key) {
                entries.removeValue(forKey: ancestor)
            }
        }
        for path in entries.keys where Self.ancestors(of: path).contains(where: keys.contains) {
            entries.removeValue(forKey: path)
        }
        let changed = entries.count != before
        if changed { dirty = true }
        lock.unlock()
        if changed { scheduleSave() }
    }

    /// Writes the cache to disk if anything changed since the last write.
    func save() {
        guard isEnabled, let fileURL, let uuid = journal.uuid() else { return }
        lock.lock()
        guard dirty else {
            lock.unlock()
            return
        }
        let snapshot = File(formatVersion: Self.formatVersion, journalUUID: uuid, entries: entries)
        dirty = false
        lastSavedAt = ContinuousClock.now
        lock.unlock()
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: [.atomic])
            // It lists folder paths in the user's home; keep it to the user.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            lock.lock()
            dirty = true
            lock.unlock()
            NSLog("Purge: couldn't save the folder size cache: %@", error.localizedDescription)
        }
    }

    var entryCount: Int {
        loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    // MARK: - Checking the journal

    /// The journal position saved sizes must be good through to be reused, or `nil`
    /// to reuse nothing this time.
    private func checkJournal() -> UInt64? {
        while checkGate.wait(timeout: .now() + .milliseconds(100)) != .success {
            if Task.isCancelled { return nil }
        }
        defer { checkGate.signal() }

        lock.lock()
        if let lastCheck {
            // A clock set backwards counts as too long ago.
            let elapsed = now().timeIntervalSince(lastCheck.at)
            if elapsed >= 0 && elapsed < Self.recheckInterval {
                lock.unlock()
                return lastCheck.eventID
            }
        }
        let snapshot = entries
        lock.unlock()

        let checkStart = journal.currentEventID()
        guard !snapshot.isEmpty else {
            recordCheck(at: checkStart)
            return checkStart
        }

        // Too old to replay cheaply, or due for a fresh measurement: measure again.
        let currentTime = now()
        let cutoff = journal.eventIDBefore(currentTime.addingTimeInterval(-Self.maxReplayAge))
        var stale = Set(snapshot.filter { path, entry in
            entry.verifiedThrough < cutoff || Self.isExpired(entry, path: path, at: currentTime)
        }.keys)
        let candidates = snapshot.filter { !stale.contains($0.key) }

        if let since = candidates.values.map(\.verifiedThrough).min(), since < checkStart {
            let roots = Self.watchRoots(for: Array(candidates.keys))
            switch journal.replay(roots, since, { Task.isCancelled }) {
            case .cancelled:
                return nil
            case .unavailable:
                stale.formUnion(candidates.keys)
            case let .changes(changedPaths, lostRoots, _):
                stale.formUnion(Self.affectedEntries(
                    candidates: candidates,
                    changedPaths: changedPaths,
                    lostRoots: lostRoots
                ))
                // A folder that was moved away, replaced, or recreated empty shows up
                // only on its parent, which changes too often to distrust everything
                // below it. Its identity changes instead.
                for (path, entry) in candidates where !stale.contains(path) {
                    if identity(path) != entry.identity {
                        stale.insert(path)
                    }
                }
            }
        }

        lock.lock()
        for (path, entry) in snapshot where entries[path] == entry {
            // Untouched since the snapshot (not re-measured or invalidated meanwhile).
            if stale.contains(path) {
                entries.removeValue(forKey: path)
            } else {
                entries[path]?.verifiedThrough = checkStart
            }
        }
        // A newer check position alone is saved at most once a minute: losing it only
        // means a longer replay next launch, and the file can be megabytes.
        let checkIsWorthSaving = lastSavedAt.map { ContinuousClock.now - $0 > .seconds(60) } ?? true
        let changed = !stale.isEmpty || checkIsWorthSaving
        if changed { dirty = true }
        lock.unlock()
        recordCheck(at: checkStart)
        if changed { scheduleSave() }
        return checkStart
    }

    private func recordCheck(at eventID: UInt64) {
        let time = now()
        lock.lock()
        lastCheck = (eventID, time)
        lock.unlock()
    }

    /// Saved folders whose size a replayed change could affect: a change in the
    /// folder or anywhere inside it, or lost events at, above or below it.
    static func affectedEntries(
        candidates: [String: Entry],
        changedPaths: [String],
        lostRoots: [String]
    ) -> Set<String> {
        var affected = Set<String>()
        for changed in changedPaths {
            let path = normalized(changed)
            if candidates[path] != nil { affected.insert(path) }
            for ancestor in ancestors(of: path) where candidates[ancestor] != nil {
                affected.insert(ancestor)
            }
        }
        for root in lostRoots.map(normalized) {
            for path in candidates.keys where isSameOrRelated(path, root) {
                affected.insert(path)
            }
        }
        return affected
    }

    /// Due for a fresh measurement: older than ``maxEntryAge``, spread by path.
    static func isExpired(_ entry: Entry, path: String, at time: Date) -> Bool {
        let age = time.timeIntervalSince(entry.measuredAt)
        return age < 0 || age > maxEntryAge * (0.75 + 0.5 * spread(of: path))
    }

    /// A stable number from 0 to 1 for a path (FNV-1a), the same in every launch.
    static func spread(of path: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Double(hash % 10_000) / 10_000
    }

    private func fullDiskAccessGranted() -> Bool {
        lock.lock()
        if let accessCheck, ContinuousClock.now - accessCheck.at < .seconds(10) {
            lock.unlock()
            return accessCheck.granted
        }
        lock.unlock()
        let granted = hasFullDiskAccess()
        lock.lock()
        accessCheck = (granted, ContinuousClock.now)
        lock.unlock()
        return granted
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        lock.lock()
        guard !saveScheduled else {
            lock.unlock()
            return
        }
        saveScheduled = true
        lock.unlock()
        saveQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.saveScheduled = false
            self.lock.unlock()
            self.save()
        }
    }

    private func loadIfNeeded() {
        lock.lock()
        guard !loaded else {
            lock.unlock()
            return
        }
        loaded = true
        lock.unlock()

        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.formatVersion == Self.formatVersion,
              file.entries.count <= Self.maxEntries,
              let uuid = journal.uuid(), uuid == file.journalUUID
        else { return }
        // The file is the user's to edit; take only entries that could be real.
        let now = journal.currentEventID()
        let valid = file.entries.filter { path, entry in
            path.hasPrefix("/") && path == Self.normalized(path) && entry.bytes >= 0 && entry.verifiedThrough <= now
        }
        lock.lock()
        entries.merge(valid) { current, _ in current }
        lock.unlock()
    }

    // MARK: - Paths

    /// "/a/b/c" → "/a/b", "/a", "/".
    static func ancestors(of path: String) -> [String] {
        var result: [String] = []
        var current = path
        while let slash = current.lastIndex(of: "/"), current != "/" {
            current = slash == current.startIndex ? "/" : String(current[..<slash])
            result.append(current)
        }
        return result
    }

    /// `a` is `b`, or one contains the other.
    static func isSameOrRelated(_ a: String, _ b: String) -> Bool {
        a == b || isInside(a, b) || isInside(b, a)
    }

    /// `path` is strictly inside `folder`.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix) && path.count > prefix.count
    }

    /// Journal paths end in "/"; saved paths don't.
    static func normalized(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// The fewest folders covering every path, so one replay sees them all. Past
    /// `maxWatchRoots`, folders are replaced by their shared parents.
    static func watchRoots(for paths: [String]) -> [String] {
        func minimalCover(_ paths: [String]) -> [String] {
            var roots = Set<String>()
            for path in Set(paths).sorted(by: { $0.count < $1.count })
            where !ancestors(of: path).contains(where: roots.contains) {
                roots.insert(path)
            }
            return roots.sorted()
        }
        var roots = minimalCover(paths)
        var depth = roots.map { $0.split(separator: "/").count }.max() ?? 0
        while roots.count > maxWatchRoots && depth > 1 {
            depth -= 1
            roots = minimalCover(roots.map { path in
                "/" + path.split(separator: "/").prefix(depth).joined(separator: "/")
            })
        }
        return roots
    }

    // MARK: - The real journal and file system

    /// The folder's identity, only when the journal reports it under this exact path:
    /// no symlinks, the same spelling as on disk, on the same disk as the home folder.
    static func liveIdentity(of path: String) -> Identity? {
        let descriptor = open(path, O_EVTONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1,
              String(cString: buffer) == path
        else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              let home = homeDevice, UInt64(info.st_dev) == home
        else { return nil }
        return Identity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            changeTime: Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
        )
    }

    private static let homeDevice: UInt64? = {
        var info = stat()
        guard stat(NSHomeDirectory(), &info) == 0 else { return nil }
        return UInt64(info.st_dev)
    }()
}

extension FolderSizeCache.Journal {
    nonisolated static let live = FolderSizeCache.Journal(
        currentEventID: { UInt64(FSEventsGetCurrentEventId()) },
        uuid: {
            var info = stat()
            guard stat(NSHomeDirectory(), &info) == 0,
                  let uuid = FSEventsCopyUUIDForDevice(info.st_dev)
            else { return nil }
            return CFUUIDCreateString(nil, uuid) as String?
        },
        eventIDBefore: { date in
            var info = stat()
            guard stat(NSHomeDirectory(), &info) == 0 else { return 0 }
            return UInt64(FSEventsGetLastEventIdForDeviceBeforeTime(info.st_dev, date.timeIntervalSince1970))
        },
        replay: { roots, since, isCancelled in
            FolderSizeCacheReplay.run(roots: roots, since: since, isCancelled: isCancelled)
        }
    )
}

/// Replays the journal under some folders, from a position up to now.
nonisolated enum FolderSizeCacheReplay {
    static func run(
        roots: [String],
        since: UInt64,
        isCancelled: @Sendable () -> Bool
    ) -> FolderSizeCache.Replay {
        guard !roots.isEmpty else { return .changes(changedPaths: [], lostRoots: [], eventCount: 0) }
        let collector = Collector(roots: roots)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(collector).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            folderSizeCacheReplayCallback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(since),
            0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        ) else { return .unavailable }
        let queue = DispatchQueue(label: "io.getpurge.folder-size-cache.replay")
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return .unavailable
        }

        let deadline = Date().addingTimeInterval(FolderSizeCache.replayTimeout)
        var outcome: FolderSizeCache.Replay?
        while outcome == nil {
            if collector.done.wait(timeout: .now() + .milliseconds(100)) == .success {
                break
            }
            if isCancelled() {
                outcome = .cancelled
            } else if Date() > deadline {
                outcome = .unavailable
            }
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        // Wait out any callback still running before reading what it collected.
        return queue.sync { outcome ?? collector.result() }
    }

    /// Gathers one replay's events. Only touched on the replay's private queue.
    final class Collector: @unchecked Sendable {
        let roots: [String]
        let done = DispatchSemaphore(value: 0)
        private var changed: [String] = []
        private var lost = Set<String>()
        private var events = 0
        private var finished = false
        private var historyLost = false

        init(roots: [String]) {
            self.roots = roots
        }

        func add(path rawPath: String, flags: FSEventStreamEventFlags) {
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 {
                if !finished {
                    finished = true
                    done.signal()
                }
                return
            }
            guard !finished else { return } // live events after the replay: not needed
            events += 1
            if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
                historyLost = true
            }
            let path = FolderSizeCache.normalized(rawPath)
            let lostMask = FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs
                    | kFSEventStreamEventFlagUserDropped
                    | kFSEventStreamEventFlagKernelDropped
                    | kFSEventStreamEventFlagRootChanged
            )
            if flags & lostMask != 0 || changed.count >= FolderSizeCache.maxChangedPaths {
                // Everything near this path is suspect; past the cap, everything is.
                let affected = changed.count >= FolderSizeCache.maxChangedPaths
                    ? roots
                    : roots.filter { FolderSizeCache.isSameOrRelated($0, path) }
                lost.formUnion(affected.isEmpty ? [path] : affected)
                return
            }
            changed.append(path)
        }

        func result() -> FolderSizeCache.Replay {
            guard finished, !historyLost else { return .unavailable }
            return .changes(changedPaths: changed, lostRoots: Array(lost), eventCount: events)
        }
    }
}

private nonisolated func folderSizeCacheReplayCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ count: Int,
    _ paths: UnsafeMutableRawPointer,
    _ flags: UnsafePointer<FSEventStreamEventFlags>,
    _ ids: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let collector = Unmanaged<FolderSizeCacheReplay.Collector>.fromOpaque(info).takeUnretainedValue()
    let pathList = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
    for index in 0..<count where index < pathList.count {
        collector.add(path: pathList[index], flags: flags[index])
    }
}
