# IRD-003: `trashIsReportedAtOnceAndEverythingElseIsFollowed` fails on this Mac (timing threshold)

> **GitHub Issue:** none - issues are disabled on `g-baskin/purge-app`. **Local placeholder number**; renumber to the GitHub issue number if issues are enabled. - Bug (test)
>
> **Status:** Backlog
> **Priority:** P2
> **Effort:** S (1-3h)
> **Reporter:** g-baskin (@g-baskin)

---

## Problem

**Observed:** `ApplicationsFolderWatcherTests/trashIsReportedAtOnceAndEverythingElseIsFollowed()` (`PurgeTests/RemovedAppWatchPolicyTests.swift:630`) fails on the fork owner's Mac. It also failed 3 of 3 runs on the original project's untouched code (`upstream-main`), so it is not caused by fork changes. The Trash report arrived after 0.8 s and slower.

**Expected:** The test passes reliably on a normally loaded developer Mac.

**Reproduction steps:**

1. `scripts/dev-test.sh -only-testing:PurgeTests/ApplicationsFolderWatcherTests/trashIsReportedAtOnceAndEverythingElseIsFollowed()`
2. Observe the `#expect(trashReport.at.timeIntervalSince(start) < 0.6)` failure (line 695), or the `#require` on line 693 if no report arrives within the 1 s wait (line 692).

*Failure counts and timings are as reported by the fork owner; not re-run by library-worker-bee.*

---

## Root cause

Not yet confirmed. The test configures `quietPeriod: .milliseconds(500)` and `pollInterval: .milliseconds(50)` (lines 651-654) and then requires the Trash departure within 0.6 s of the first move, leaving about 100 ms of headroom for FSEvents latency, scheduling and the poll. This looks like a threshold that is too tight for slower or busier machines rather than a product bug; that must be confirmed before changing the test (check whether `ApplicationsFolderWatcher` (`purge/Services/ApplicationsFolderWatcher.swift`) really reports Trash moves "at once", i.e. without waiting for the quiet period).

---

## Fix plan

1. Instrument once: log the time from move to FSEvents callback to `onDeparture` to see where the 0.8 s goes.
2. If the watcher reports correctly but late because of FSEvents latency, relax the assertion to compare against the other kinds (Trash must be reported before the deleted / followed apps, and well before `quietPeriod + movedFollowWindow`) instead of an absolute 0.6 s, and widen the wait on line 692.
3. If the watcher actually waits for the quiet period on Trash moves, that is a product bug: fix the watcher instead and keep the threshold.
4. Consider proposing the change upstream (`jithin-sabu/purge-app`), since the test fails there too.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | The test passes 10/10 runs on the fork owner's Mac, alone and in the full suite. |
| AC-2 | The test still fails if the watcher waits for the quiet period before reporting a Trash move. |

---

## Files touched (expected)

- `PurgeTests/RemovedAppWatchPolicyTests.swift`
- possibly `purge/Services/ApplicationsFolderWatcher.swift`

---

## Out of scope

- `ScanQueueStoreTests` flakiness ([IRD-004](../ird-004-scan-queue-store-test-timeouts/ird-004-scan-queue-store-test-timeouts-index.md)).

---

## Related

- [IRD-004](../ird-004-scan-queue-store-test-timeouts/ird-004-scan-queue-store-test-timeouts-index.md)
