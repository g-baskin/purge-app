# PRD-007: Time Machine Local Snapshots

> **Status:** Backlog
> **Priority:** P3
> **Effort:** L (1-3d) *(roadmap estimate: Small-Medium, 2 days)*
> **Schema changes:** None
> **Source:** `docs/ROADMAP.md` item 7 (open). No `tmutil` usage exists in `purge/` today.

---

## Overview

Local APFS snapshots are a hidden source of "System Data". Purge should list them and offer to thin them, with clear text.

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

- List snapshots with `tmutil listlocalsnapshots /` via `ProcessRunner` and show their dates.
- Offer thinning with `tmutil thinlocalsnapshots` behind a clear confirmation, labelled `medium`.
- Show count and dates only - sizes are not reliably reported, so no fake byte numbers.

## Non-Goals

- Deleting individual snapshots by name, or touching Time Machine backup disks.
- Including snapshots in one-click or scheduled cleaning.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given canned `tmutil` output (including none, one, many, and malformed lines), the parser returns the right dates. |
| AC-2 | No byte size is shown for snapshots anywhere. |
| AC-3 | Thinning runs only after explicit confirmation, reports success or failure honestly, and is recorded in Cleanup History as not restorable. |
| AC-4 | A `tmutil` failure or timeout shows a message and never blocks the scan. |

---

## Open questions

- [ ] This is the one feature that frees space without the Trash. Does it fit the "Trash by default" rule, and how is that explained? (Likely needs an ADR.)
- [ ] Does `thinlocalsnapshots` need admin rights on current macOS, and if so, does it go through the helper?
- [ ] Which mode shows it - General, or the Overview disk breakdown?

---

## Related

- `docs/ROADMAP.md` item 7
