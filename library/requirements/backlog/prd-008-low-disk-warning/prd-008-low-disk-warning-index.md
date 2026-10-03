# PRD-008: Low-Disk Warning (Menu Bar)

> **Status:** Backlog
> **Priority:** P2
> **Effort:** M (3-8h) *(roadmap estimate: Small, 1 day)*
> **Schema changes:** None (new preferences only)
> **Source:** `docs/ROADMAP.md` item 8 (open).

---

## Overview

Notify the user once when free space drops below a level they choose, with a way to review safe items.

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

- Read free space with `VolumeCapacityReader.read(for:)` (`purge/Services/VolumeCapacityReader.swift:20`).
- Notify once when free space falls below a user-set level (default 10%), with a "Review safe items" action that opens the main window.
- Rate-limit to at most once a day; re-arm after space recovers above the level.
- Setting in Settings to change the level or turn the warning off.

## Non-Goals

- Cleaning automatically when the warning fires.
- Monitoring volumes other than the home volume in v1.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given capacity below the level and no warning today, then exactly one notification is delivered. |
| AC-2 | Given a warning already delivered today, then no second one is delivered (injected clock). |
| AC-3 | Given space recovers and then drops again on a later day, then a new warning is delivered. |
| AC-4 | The action opens the main window on safe items. |
| AC-5 | With notifications denied, nothing crashes and the menu bar can still show the state. |

---

## Implementation notes

- Reuse the notification plumbing in `purge/Services/ScheduledCleanupNotifier.swift` (`requestAuthorizationIfNeeded`, `deliver`) and the menu bar in `purge/Menu/` (`MenuBarView.swift`, `AppWindowPresenter.swift`).

---

## Open questions

- [ ] Where does the check run while the main window is closed - the menu bar app, or the `PurgeWatch` agent (`io.getpurge.watch`)?
- [ ] How often to poll, and should it use a volume notification instead?

---

## Related

- `docs/ROADMAP.md` item 8
