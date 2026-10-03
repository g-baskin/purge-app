# IRD-004: `ScanQueueStoreTests` time out under load (5 s wait)

> **GitHub Issue:** none - issues are disabled on `g-baskin/purge-app`. **Local placeholder number**; renumber to the GitHub issue number if issues are enabled. - Bug (test)
>
> **Status:** Backlog
> **Priority:** P3
> **Effort:** XS (< 1h)
> **Reporter:** g-baskin (@g-baskin)

---

## Problem

**Observed:** `PurgeTests/ScanQueueStoreTests.swift` (16 tests) waits for state changes with `eventually(timeout: 5)` (lines 356-366). Under full-suite load one check once took 6.6 s and failed. Run alone, 16/16 pass.

**Expected:** The suite passes under load without hiding real hangs.

**Reproduction steps:**

1. Run the full suite with `scripts/dev-test.sh` on a busy machine.
2. Occasionally a `ScanQueueStoreTests` check returns `false` from `eventually`.

*Timings as reported by the fork owner; not re-run by library-worker-bee.*

---

## Root cause

Not confirmed. Likely the 5 s polling deadline is shorter than the worst-case scheduling delay when many tests run in parallel. No product defect has been identified.

---

## Fix plan

1. Raise the default `timeout` in `eventually` (e.g. to 15-30 s). Passing runs still finish as soon as the condition holds, so this costs nothing when green.
2. Optionally mark the suite `.serialized` if parallel load is the cause.
3. Do not raise it so far that a real hang takes minutes to report.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | 10 consecutive full-suite runs show no `ScanQueueStoreTests` timeout. |
| AC-2 | A deliberately stuck scan still fails the test within the new timeout. |

---

## Files touched (expected)

- `PurgeTests/ScanQueueStoreTests.swift`

---

## Out of scope

- [IRD-003](../ird-003-trash-report-timing-test/ird-003-trash-report-timing-test-index.md) (watcher timing test).

---

## Related

- [IRD-003](../ird-003-trash-report-timing-test/ird-003-trash-report-timing-test-index.md)
