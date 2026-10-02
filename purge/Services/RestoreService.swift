import Foundation

/// Whether a cleaned history row can be put back right now. Computed from disk,
/// never stored, so it stays true after the user empties the Trash or reinstalls.
nonisolated enum RestoreAvailability: Equatable, Sendable {
    /// At least one piece is still in the Trash and its original spot is free.
    case restorable
    /// Still in the Trash, but something new now sits at the original path.
    case conflict
    /// Nothing left in the Trash to put back (emptied, or already restored).
    case noLongerInTrash
    /// Never recorded (older history, or removed outright like simulators).
    case notRestorable
}

nonisolated enum RestorePieceOutcome: Equatable, Sendable {
    case restored
    case conflict
    case missingFromTrash
    case refused
    case failed(String)
}

nonisolated struct RestoreReport: Equatable, Sendable {
    var restoredCount = 0
    var conflictCount = 0
    var missingCount = 0
    var failedCount = 0

    var summary: String {
        var parts: [String] = []
        if restoredCount > 0 { parts.append("Put back \(restoredCount) item\(restoredCount == 1 ? "" : "s")") }
        if conflictCount > 0 { parts.append("\(conflictCount) skipped: something new is already there") }
        if missingCount > 0 { parts.append("\(missingCount) no longer in Trash") }
        if failedCount > 0 { parts.append("\(failedCount) could not be moved") }
        return parts.isEmpty ? "Nothing to put back" : parts.joined(separator: " · ")
    }
}

/// Moves items Purge sent to the Trash back where they came from.
///
/// Fails closed: a piece is only moved when its trashed copy sits inside a known
/// Trash folder, its original path is inside `allowedRoot` (or is an app bundle in
/// an Applications folder), and nothing exists at the original path. It never overwrites.
nonisolated struct RestoreService: Sendable {
    let trashRoots: [URL]
    let allowedRoot: URL
    /// Where uninstalled apps go back to. `~/Applications` is already inside the home folder.
    let applicationsRoots: [URL]

    init(
        trashRoots: [URL] = TrashStore.trashDirectories(),
        allowedRoot: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsRoots: [URL] = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
    ) {
        self.trashRoots = trashRoots.map(\.standardizedFileURL)
        self.allowedRoot = allowedRoot.standardizedFileURL
        self.applicationsRoots = applicationsRoots.map(\.standardizedFileURL)
    }

    func availability(of item: CleanupHistoryDeletedItemDTO) -> RestoreAvailability {
        guard let pieces = item.trashedPieces, !pieces.isEmpty else { return .notRestorable }
        var sawConflict = false
        for piece in pieces where isAcceptable(piece) {
            let fm = FileManager.default
            guard Self.exists(piece.trashedPath, fm) else { continue }
            if Self.exists(piece.originalPath, fm) {
                sawConflict = true
            } else {
                return .restorable
            }
        }
        return sawConflict ? .conflict : .noLongerInTrash
    }

    func restore(_ items: [CleanupHistoryDeletedItemDTO]) -> RestoreReport {
        var report = RestoreReport()
        for piece in items.flatMap({ $0.trashedPieces ?? [] }) {
            switch restore(piece) {
            case .restored: report.restoredCount += 1
            case .conflict: report.conflictCount += 1
            case .missingFromTrash: report.missingCount += 1
            case .refused, .failed: report.failedCount += 1
            }
        }
        return report
    }

    func restore(_ piece: TrashedPiece) -> RestorePieceOutcome {
        guard isAcceptable(piece) else {
            NSLog("Purge: refused to restore %@ from %@", piece.originalPath, piece.trashedPath)
            return .refused
        }
        let fm = FileManager.default
        guard Self.exists(piece.trashedPath, fm) else { return .missingFromTrash }
        guard !Self.exists(piece.originalPath, fm) else { return .conflict }

        let source = URL(fileURLWithPath: piece.trashedPath)
        let destination = URL(fileURLWithPath: piece.originalPath)
        do {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fm.moveItem(at: source, to: destination)
            // The folders it went back into, and the Trash it left, changed size.
            FolderSizeCache.shared.invalidate([destination, source.deletingLastPathComponent()])
            return .restored
        } catch {
            NSLog("Purge: failed to restore %@ — %@", piece.originalPath, error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    /// History is a file on disk; treat its paths as untrusted.
    func isAcceptable(_ piece: TrashedPiece) -> Bool {
        let trashed = URL(fileURLWithPath: piece.trashedPath).standardizedFileURL
        let original = URL(fileURLWithPath: piece.originalPath).standardizedFileURL
        guard piece.trashedPath.hasPrefix("/"), piece.originalPath.hasPrefix("/") else { return false }
        guard trashRoots.contains(where: { Self.isStrictlyInside(trashed, $0) }) else { return false }
        guard Self.isStrictlyInside(original, allowedRoot) || isAppBundleLocation(original) else { return false }
        // Never "restore" into a Trash folder.
        guard !trashRoots.contains(where: { Self.isStrictlyInside(original, $0) || original == $0 }) else {
            return false
        }
        return true
    }

    /// An app bundle directly in an Applications folder, or one vendor folder below
    /// it: the only places outside the home folder the uninstaller takes things from.
    private func isAppBundleLocation(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app" else { return false }
        let parent = url.deletingLastPathComponent()
        let rootPaths = Set(applicationsRoots.map(\.path))
        if rootPaths.contains(parent.path) { return true }
        return parent.pathExtension.lowercased() != "app"
            && rootPaths.contains(parent.deletingLastPathComponent().path)
    }

    private static func isStrictlyInside(_ url: URL, _ root: URL) -> Bool {
        let path = url.path
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return path.hasPrefix(rootPath) && path.count > rootPath.count
    }

    /// Counts broken symlinks as present, so they are never overwritten.
    private static func exists(_ path: String, _ fm: FileManager) -> Bool {
        (try? fm.attributesOfItem(atPath: path)) != nil
    }
}
