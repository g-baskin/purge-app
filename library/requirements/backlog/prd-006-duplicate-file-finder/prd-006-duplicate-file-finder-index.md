# PRD-006: Duplicate File Finder

> **Status:** Backlog
> **Priority:** P2
> **Effort:** L (1-3d) *(roadmap estimate: Medium, 3-4 days)*
> **Schema changes:** None
> **Source:** `docs/ROADMAP.md` item 5 (open).

---

## Overview

The roadmap asks for a duplicate finder reusing Large Files folders and UI. **Partly exists upstream:** `purge/Services/DuplicateFileDetector.swift` (upstream commit `390a0b7`, issue #17) already finds byte-identical files *among Large Files scan results*: bucket by size, 64 KB head + tail sample digest, then full streaming digest; hard links collapsed; APFS clones not detected. `purge/Models/DuplicateKeeper.swift` suggests (visibly, overridably) which copy to keep, and `LargeFileDeletionConfirmSheet` (`purge/Views/LargeFilesView.swift:1273`) warns when a selection removes every copy. This PRD covers the gap between that and the roadmap item.

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

- Find duplicates below the Large Files threshold (roadmap default minimum 1 MB; Large Files thresholds start at 5 MB, `purge/Models/LargeFile.swift:275`), using the same folders and exclusions as `LargeFileScanPolicy`.
- "Keep newest / keep oldest / keep in folder X" selection helpers.
- One copy per group always kept: the UI can never select every copy (roadmap requirement; today it only warns).
- Label `medium`; never in one-click or scheduled cleaning.

## Non-Goals

- Whole-disk duplicate search outside the Large Files folders (upstream rejected that scope in the detector's design notes).
- Near-duplicate / similar-image detection.
- Choosing a survivor silently (issue #17).

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given fixtures with duplicates, near-duplicates (same size, different content) and hard links, then groups contain exactly the true duplicates. |
| AC-2 | Files between 1 MB and the Large Files threshold are grouped when the duplicate mode is on. |
| AC-3 | Each helper selects all but one copy by its rule; ties are deterministic. |
| AC-4 | The app cannot submit a deletion that removes every copy in a group (tested at the model level, not only in the view). |
| AC-5 | Duplicates never appear in one-click or scheduled cleaning. |

---

## Open questions

- [ ] Replace the "every copy" warning with a hard block, or keep the warning as an explicit override? Upstream treats this as the user's call.
- [ ] APFS clones overstate reclaimable bytes; is there an acceptable way to flag them?
- [ ] Separate sidebar mode, or a lower threshold inside Large Files?

---

## Related

- `docs/ROADMAP.md` item 5
- Upstream issue #17 (jithin-sabu/purge-app)
