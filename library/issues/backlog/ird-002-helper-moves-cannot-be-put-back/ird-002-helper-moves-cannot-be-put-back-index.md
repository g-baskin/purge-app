# IRD-002: Items moved by the privileged helper can't be put back

> **GitHub Issue:** none - issues are disabled on `g-baskin/purge-app`. **Local placeholder number**; renumber to the GitHub issue number if issues are enabled. - Enhancement
>
> **Status:** Backlog
> **Priority:** P2
> **Effort:** M (3-8h) *(estimate)*
> **Reporter:** g-baskin (@g-baskin)

---

## Problem

**Observed:** When an uninstall's ordinary move to the Trash fails (admin-owned app) and Purge falls back to the root helper, the item does move to the Trash, but its Cleanup History row shows no **Put Back** button (`RestoreAvailability.notRestorable`).

**Expected:** Helper-moved items can be put back like any other item, or the UI says why not.

**Reproduction steps:**

1. Install an app into `/Applications` owned by root (e.g. via an admin installer).
2. Uninstall it with Purge; approve the helper.
3. Open Settings -> Cleanup History -> the entry. The app row has no Put Back.

---

## Root cause

The XPC reply carries only which paths moved, not where they landed:
- `PurgeHelperProtocol.moveToTrashReportingOwnership(paths:withReply:)` replies `(movedPaths, ownershipIncompletePaths)` (`purge/PrivilegedHelper/PurgeHelperProtocol.swift:175-178`); the legacy `moveToTrash` replies `movedPaths` only.
- The helper does know the final name: `HelperService.secureMoveToTrash` renames into the user's `~/.Trash` under a unique name with `RENAME_EXCL` (`PurgeHelper/HelperService.swift:187-230`).
- `FileDeleter.applyPrivilegedFallback` -> `recordMoved` builds `DeletedItem` without `trashedPieces` (`purge/Services/FileDeleter.swift:390-429`), as documented on `DeletedItem.trashedPieces` (lines 11-13).

---

## Fix plan

1. Add a new helper method (do not change existing selectors, for wire compatibility between app and helper versions) that replies with `[originalPath: trashedPath]` as well as ownership info; bump `PurgeHelperConstants.version` (`PurgeHelperProtocol.swift:18`, currently `"3"`) so `reconcileVersion` re-registers an older helper.
2. Return the landed name from `secureMoveToTrash` and include it in the reply.
3. Thread it through `PrivilegedMoveResult` (`purge/PrivilegedHelper/PrivilegedUninstall.swift`) and `PrivilegedHelperManager` into `recordMoved`, producing `TrashedPiece`s.
4. Decide how restoring works: `RestoreService` already allows app bundles back into `/Applications` (`RestoreService.swift:129-138`), but moving a root-owned bundle back may need the helper again (a new, tightly scoped "restore from Trash" call validated against the same allowed locations). Alternatively, show a clear "Put back in Finder" hint for these rows.
5. Keep failing closed: helper-supplied Trash paths still pass `RestoreService.isAcceptable`.

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given an app moved by the helper, when the history sheet opens, then its row is `restorable` while the bundle is still in the Trash. |
| AC-2 | Given that row, when the user clicks Put Back, then the bundle returns to its original Applications path, or a clear message explains why it cannot. |
| AC-3 | An older helper (version 3) still works for uninstall; rows from it remain `notRestorable`. |
| AC-4 | Tests cover the new reply mapping and a fake helper result end to end through `FileDeleter` and `RestoreService`. |

---

## Files touched (expected)

- `purge/PrivilegedHelper/PurgeHelperProtocol.swift`
- `PurgeHelper/HelperService.swift`
- `purge/PrivilegedHelper/PrivilegedHelperManager.swift`, `purge/PrivilegedHelper/PrivilegedUninstall.swift`
- `purge/Services/FileDeleter.swift`, possibly `purge/Services/RestoreService.swift`
- `PurgeTests/RestoreServiceTests.swift` and helper tests

---

## Out of scope

- Restoring items removed outright (simulators).
- Changing the helper's code-signing requirements ([PRD-003](../../../requirements/completed/prd-003-local-dev-signing/prd-003-local-dev-signing-index.md)).

---

## Related

- [PRD-001: Put Back](../../../requirements/completed/prd-001-put-back/prd-001-put-back-index.md)
- `SECURITY.md` (any new root helper method needs security review)
