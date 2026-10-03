# PRD-004: iPhone/iPad Backups and iOS Update Files

> **Status:** Backlog
> **Priority:** P2
> **Effort:** M (3-8h) *(roadmap estimate: Small, 1-2 days)*
> **Schema changes:** None
> **Source:** `docs/ROADMAP.md` item 3 (open).

---

## Overview

Device backups in `~/Library/Application Support/MobileSync/Backup` and downloaded iOS/iPadOS firmware (`.ipsw`) are often 10-100 GB and invisible to most users. Purge should show them. **Caution:** the original project deliberately never touches iPhone backups: `DeletionSafetyPolicy.swift:259-261` and `CacheScanner.swift:514-516` state backups are non-recoverable and "must never be scanned, sized, or shown", and `CacheDiscoveryPaths.excludedApplicationSupportRoots` excludes `MobileSync`. This PRD must decide (Open questions) whether to reverse that for backups or ship only the `.ipsw` part.

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

- List `.ipsw` files in `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates` as `safe` (re-downloadable) and cleanable.
- If approved: list each backup under `MobileSync/Backup/*` with device name and last backup date read from its `Info.plist`, labelled `medium`, Trash-only.
- Show both in General mode as a new group with an explanation entry.

## Non-Goals

- Backups in one-click "Clean Safe Items" or scheduled cleaning - never.
- Encrypted-backup inspection, partial backup pruning, or Finder/iCloud backup management.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given a fake home with `.ipsw` files, when General mode scans, then each appears labelled `safe` with its size and is cleanable. |
| AC-2 | Given a fake backup folder with an `Info.plist`, when scanned (if backups are approved), then it shows the device name and last backup date, labelled `medium`. |
| AC-3 | Backups are never selected by "Clean Safe Items" or included by scheduled cleaning (tested). |
| AC-4 | Deleting a backup moves it to the Trash and is recorded in Cleanup History with Put Back pieces ([PRD-001](../../completed/prd-001-put-back/prd-001-put-back-index.md)). |
| AC-5 | The `DeletionSafetyPolicy` allowlist change is the narrowest possible (exact folders), with tests that sibling paths stay refused. |

---

## Implementation notes

- `purge/Services/CacheScanner.swift` (`systemJunkLocations`), `purge/Services/DeletionSafetyPolicy.swift`, `purge/Services/CacheDiscoveryPaths.swift`, `purge/Resources/explanations.json`.
- Reading backup folders needs Full Disk Access.

---

## Open questions

- [ ] Reverse the upstream "never show backups" decision, or ship `.ipsw` only? If reversed, record the decision (ADR) and explain the risk in the UI.
- [ ] Should backups be "show and reveal in Finder" only, with no delete button, as a middle ground?

---

## Related

- `docs/ROADMAP.md` item 3
- [PRD-001: Put Back](../../completed/prd-001-put-back/prd-001-put-back-index.md)
