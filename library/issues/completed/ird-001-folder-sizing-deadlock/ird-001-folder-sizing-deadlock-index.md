# IRD-001: Folder sizing hangs forever when many measurements run at once

> **GitHub Issue:** none - issues are disabled on `g-baskin/purge-app`. **Local placeholder number**; renumber to the GitHub issue number if issues are enabled. - Bug
>
> **Status:** Resolved (commit `80d10c1`, 2026-10-02)
> **Priority:** P0 (scans hung permanently)
> **Effort:** S (1-3h)
> **Reporter:** g-baskin (@g-baskin)

---

## Problem

**Observed:** Scans could hang for good. `FolderSizing.directorySizes(at:)` (`purge/Utilities/FolderSizing.swift`) split folders into chunks of `duChunkSize = 64`, dispatched each chunk's `du` onto `DispatchQueue.global(qos: .utility)`, and blocked the caller on a `DispatchGroup`. Scanners call it from many threads at once. Once the blocked callers occupied every GCD worker thread, no thread was left to run the `du` work, so every call waited forever. On an 8-core Mac eight concurrent callers were enough.

**Expected:** Any number of concurrent callers finish.

**Reproduction (from the commit message):** a standalone check with sixteen concurrent callers hung with the old code and finished in under a second with the new.

---

## Root cause

Thread-pool starvation: callers blocked GCD's shared, width-limited pool while waiting for work that needed that same pool.

---

## Fix (as shipped)

In `FolderSizing.measure(_:)` (`purge/Utilities/FolderSizing.swift`, around lines 93-140):

1. A single chunk now runs inline on the calling thread (`if chunks.count == 1 { return directorySizesForChunk(chunks[0]) }`).
2. Several chunks each run on a dedicated `Thread` (`qualityOfService = .utility`) instead of the global queue. Each thread is started only after taking a permit from the process-wide `duChunkLimiter` (`maxConcurrentDuChunks = 10`), so at most ten exist at once and they never depend on the shared pool.

The later size cache ([PRD-002](../../../requirements/completed/prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md)) follows the same rule: private queues, never GCD's shared pool.

---

## Acceptance criteria

| ID | Criterion | Test (`PurgeTests/FolderSizingConcurrencyTests.swift`) |
|---|---|---|
| AC-1 | Twice as many concurrent single-chunk callers as the Mac has cores all finish. | `manyConcurrentSmallMeasurementsFinish` |
| AC-2 | Twice as many concurrent multi-chunk callers as cores all finish. | `manyConcurrentMultiChunkMeasurementsFinish` |
| AC-3 | Existing limiter, cancellation and correctness tests still pass. | `measuresAllChunksUnderFanOut`, `concurrentCallersEachGetCompleteResults`, `cancellationDoesNotLeakLimiterPermits`, `chunkAndDirectorySizesShareLimiter`, `chunkCancellationDoesNotLeakLimiterPermits`, `toleratesUnreadableDirectories` |

Verification for this IRD: commit message and diff read; tests not re-run by library-worker-bee.

---

## Files touched

- `purge/Utilities/FolderSizing.swift` (+15 / -1)
- `PurgeTests/FolderSizingConcurrencyTests.swift` (+47)

---

## Out of scope

- Caching sizes between scans (that is [PRD-002](../../../requirements/completed/prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md)).

---

## Related

- [PRD-002: Saved folder sizes](../../../requirements/completed/prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md)
