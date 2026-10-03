# PRD-002: Saved Folder Sizes (FSEvents-backed size cache) *(Retroactive)*

> **Status:** Shipped
> **Priority:** - *(retroactive - work is done)*
> **Effort:** L (1-3d) *(estimated after the fact)*
> **Schema changes:** Additive (new on-disk cache file, no change to existing data)
> **Written:** October 2026
> **Retroactive:** Yes - this PRD was written after implementation.
> **Shipped in:** commit `2f5d327` (2026-10-02). Builds on the deadlock fix in `80d10c1` ([IRD-001](../../../issues/completed/ird-001-folder-sizing-deadlock/ird-001-folder-sizing-deadlock-index.md)). Fork-only.

---

## What was built

Every scan used to walk every folder with `du` on every launch. Purge now saves folder sizes between launches together with the position in the macOS FSEvents journal they are known to be good through. Before reusing a size, the cache replays the journal from that position and re-measures only folders something changed inside.

**Measured on a real 8-core Mac (from the commit message of `2f5d327`):** 525 cache and Application Support folders; first scan 25 s; relaunch 0.9 s with 24 folders walked and 501 reused; every reused size matched a fresh `du`. *Not re-measured for this PRD.*

### How it works

- **Entry points.** `FolderSizing.directorySizesForChunk(_:)` and `FolderSizing.directorySizes(at:)` (`purge/Utilities/FolderSizing.swift:42-44`, `91-93`) route through `FolderSizeCache.shared.sizes(for:measure:)`; the `measure` closure (real `du`) receives only folders that need a walk.
- **Reuse rule** (`purge/Utilities/FolderSizeCache.swift:135-186`). A saved size is reused only if its `verifiedThrough` journal position is at or after the position returned by `checkJournal()` and the entry is not expired. Everything else is measured. The journal position and folder identities are captured *before* measuring, so a change during the walk shows up at the next check rather than being covered by this measurement.
- **Journal replay** (`checkJournal()`, line 248; `Journal` abstraction line 79, live implementation via `FSEventStreamCreate` around line 545). Replays from the oldest saved position over watch roots (folders collapsed to shared parents above `maxWatchRoots = 256`, `watchRoots(for:)` line 463), then forgets every saved size a change could touch (`affectedEntries`, line 333): a change in the folder or inside it, or lost events at, above or below it.
- **Folder identity.** Each entry stores the folder's inode and `st_ctime` (`Identity`, lines 59-67; `liveIdentity`, line 487). Replacing, recreating, or moving a folder away and back changes the identity and forces a re-measure, covering changes the journal reports only on the parent.
- **Fails toward measuring.** Everything is re-measured when: the journal UUID changed (reset), events were lost, the replay exceeded `replayTimeout = 20 s`, the last check is older than `maxReplayAge = 8 h`, or there are more than `maxChangedPaths = 100 000` changed paths. Each size is also re-measured about once a day regardless (`maxEntryAge = 24 h`, spread 18-30 h per path so they don't expire together, lines 27-31, `isExpired`/`spread` lines 355-368), because files held open and written continuously are reported only when closed. Folders reported under a different path (symlinks, other disks) are never trusted. More than `maxEntries = 50 000` entries resets the cache.
- **Full Disk Access gate** (line 136, `fullDiskAccessGranted()` line 370, re-checked at most every 10 s). Without FDA the cache is skipped entirely and every folder is measured, because macOS may hide changes in folders Purge can't read.
- **Concurrency.** One journal check at a time; concurrent callers within `recheckInterval = 2 s` share it. Work runs on private queues, never GCD's shared pool (lesson from IRD-001).
- **Purge's own changes.** `FileDeleter.forgetSavedSizes(around:)` (`purge/Services/FileDeleter.swift:370`, called via `defer` at lines 121 and 285) and `RestoreService.restore(_:)` (`purge/Services/RestoreService.swift:107`) call `invalidate(_:)` (line 190), which forgets the folders, everything inside them, every ancestor, and the Trash folders, so the next scan sees the change at once.
- **Persistence.** `~/Library/Application Support/io.getpurge.app/folder-size-cache.json`, written atomically with permissions `0600` (lines 212-230), debounced by 2 s (`scheduleSave`, line 384). `formatVersion = 1` discards older formats. Disabled in the test host (`TestHost.isActive()`, line 44) so tests always measure for real.

## Goals (met)

- Relaunch scans reuse sizes for unchanged folders.
- Never show a stale size when the journal cannot vouch for it.
- Purge's own deletions and Put Back are reflected immediately.

## Non-Goals

- Watching folders live while Purge is idle (the journal is replayed on demand).
- Caching sizes without Full Disk Access.

---

## Acceptance criteria (verified by tests)

Tests: `PurgeTests/FolderSizeCacheTests.swift` (fake journal plus two tests against the real one).

| ID | Criterion | Test |
|---|---|---|
| AC-1 | Unchanged folders are reused, not walked. | `reusesUnchangedFolders` |
| AC-2 | A change inside a folder re-measures it; a change only in its parent does not. | `remeasuresAfterAChangeInside`, `parentChangeKeepsTheSize` |
| AC-3 | A replaced / moved folder is re-measured. | `identityChangesMeasureAgain`, `identityRules` |
| AC-4 | Lost events, an unavailable journal, or a too-old check measure again. | `lostEventsMeasureAgain`, `unavailableJournalMeasuresAll`, `tooOldToReplayIsMeasured` |
| AC-5 | Without Full Disk Access, every call measures. | `noAccessMeasuresEveryTime` |
| AC-6 | A change during the walk is caught at the next check. | `changeDuringWalkIsCaught` |
| AC-7 | Failed or unfollowable measurements are not saved. | `failedMeasurementIsNotSaved`, `unfollowableFolderIsNotSaved` |
| AC-8 | `invalidate` forgets the folder, its contents and its ancestors. | `invalidateForgetsRelatedFolders` |
| AC-9 | Sizes expire about daily. | `expiredSizesAreMeasuredAgain` |
| AC-10 | Cache survives a reload from disk. | `persistence` |
| AC-11 | Concurrent scans share one journal check. | `concurrentScansShareOneCheck` |
| AC-12 | Watch roots cover every saved folder. | `watchRootsCoverAll` |
| AC-13 | The real FSEvents journal reports a change inside a temp folder. | `journalReportsChangesInside` |

---

## Data model changes

New file `folder-size-cache.json`: `{ formatVersion, journalUUID, entries: { path: { bytes, verifiedThrough, identity, ... } } }` (`File`, line 89).

---

## Known limits

- **Needs Full Disk Access**; without it Purge measures every time (same speed as before).
- Replaying a long gap is slow: the code notes six hours of changes replayed in about 6 s on an 8-core Mac, hence the 8 h cut-off.
- Busy folders (logs, databases held open) can lag by up to a day before the forced re-measure.
- The headline timings are from one Mac and one run (the commit message); there is no automated performance test.
- Folders on other volumes or behind symlinks are always walked.

---

## Related

- [IRD-001: Folder sizing deadlock](../../../issues/completed/ird-001-folder-sizing-deadlock/ird-001-folder-sizing-deadlock-index.md)
- [PRD-001: Put Back](../prd-001-put-back/prd-001-put-back-index.md) - restores invalidate saved sizes.
