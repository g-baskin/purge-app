# PRD-001: Put Back *(Retroactive)*

> **Status:** Shipped
> **Priority:** - *(retroactive - work is done)*
> **Effort:** M (3-8h) *(estimated after the fact)*
> **Schema changes:** Additive (optional `trashedPieces` on Cleanup History items)
> **Written:** October 2026
> **Retroactive:** Yes - this PRD was written after implementation.
> **Shipped in:** commit `d9f7d5f` (2026-10-02), Put Back text styling fixed in `5d7cd9a` (2026-10-02). Fork-only; not in upstream `jithin-sabu/purge-app`.

---

## What was built

Purge never deletes; it moves items to the Trash. Before this change, getting something back meant finding it in the Finder Trash by hand, where a "contents only" clean leaves many loosely named children. Put Back lets the user restore items straight from **Settings -> Cleanup History**: each cleaned row in the history detail sheet gets a **Put Back** button, and the sheet header has **Put Back All**.

### How it works

1. **Recording where things land.** `FileDeleter.moveToTrash(_:)` (`purge/Services/FileDeleter.swift:376`) calls `FileManager.trashItem(at:resultingItemURL:)` and returns a `TrashedPiece` (original path + path inside the Trash). A normal clean records one piece; a "contents only" clean (`DeletionSafetyPolicy.shouldDeleteContentsOnly`) records one piece per child it moved (`FileDeleter.swift:157-195`). When the system reports no landing location, the move still happens but no piece is recorded.
2. **Persisting.** `TrashedPiece` and the optional `trashedPieces` field live in `purge/Models/CleanupHistoryEntry.swift:10-24`. `CleanupHistoryStore.append(trigger:report:)` (`purge/Services/CleanupHistoryStore.swift:44-50`) copies pieces into history, storing `nil` when there are none. Manual and scheduled cleans both record pieces. Older history without the field still decodes and is shown as not restorable.
3. **Deciding what can be put back.** `RestoreService.availability(of:)` (`purge/Services/RestoreService.swift:61`) is computed from disk every time the sheet opens, never stored. States (`RestoreAvailability`, lines 5-14): `restorable`, `conflict` (something new sits at the original path), `noLongerInTrash` (emptied or already restored), `notRestorable` (no pieces: older history, or items removed outright such as simulators via `simctl delete`).
4. **Restoring.** `RestoreService.restore(_:)` (lines 76-112) moves each acceptable piece back with `FileManager.moveItem`, re-creating missing parent folders. It never overwrites: if anything exists at the original path (including a broken symlink, lines 146-150) the piece is skipped as a conflict. After a move it invalidates saved folder sizes for the destination and the Trash folder it left (see [PRD-002](../prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md)). Results are summarised by `RestoreReport.summary` (lines 24-38), for example "Put back 3 items · 1 skipped: something new is already there".
5. **Fails closed on untrusted history.** History is a file on disk, so `isAcceptable(_:)` (lines 114-127) rejects any piece unless both paths are absolute, the trashed copy is strictly inside a known Trash folder (`TrashStore.trashDirectories()`), and the original is strictly inside the home folder or is an app bundle directly in `/Applications` (or one vendor folder below it, lines 129-138). It never restores into a Trash folder. Refusals are logged with `NSLog`.
6. **UI.** `purge/Views/CleanupHistoryDetailView.swift` (opened from `SettingsView.swift:77`) refreshes availability on `.task`, runs restores on a detached task so large folders don't block the main thread (lines 56-66), shows a progress indicator and the summary message, and per row shows **Put Back**, "Already replaced" or "Not in Trash" (lines 175-195). Text uses design-system font and colour tokens (`5d7cd9a`).

## Goals (met)

- Restore any item Purge itself moved to the Trash, from the history row that recorded it.
- Never overwrite a file or folder at the original location.
- Treat the history file as untrusted input; move nothing outside the Trash -> home / Applications path pair.
- Keep older history readable.

## Non-Goals

- Restoring items removed outright (simulators) - they never went to the Trash.
- Restoring after the Trash is emptied.
- Restoring items moved by the privileged helper (see Known limits).

---

## Acceptance criteria (verified by tests)

Tests: `PurgeTests/RestoreServiceTests.swift`.

| ID | Criterion | Test |
|---|---|---|
| AC-1 | A trashed file goes back to its original path, re-creating a missing parent folder. | `restoresFileAndRecreatesMissingParent` |
| AC-2 | Something new at the original path is never overwritten; reported as a conflict. | `neverOverwritesSomethingNewAtOriginalPath` |
| AC-3 | An emptied Trash is reported as "no longer in Trash", not as a failure. | `emptiedTrashIsReportedNotFailed` |
| AC-4 | History written before Put Back is not restorable. | `oldHistoryWithoutPiecesIsNotRestorable` |
| AC-5 | A contents-only clean restores every piece. | `contentsOnlyCleanRestoresEveryPiece` |
| AC-6 | Paths outside the Trash / home folder are refused. | `refusesPathsOutsideTrashOrHome` |
| AC-7 | App bundles are restored only into Applications folders. | `restoresAppBundlesOnlyIntoApplicationsFolders` |
| AC-8 | A real `FileDeleter` clean can be put back end to end. | `realCleanCanBePutBack` |
| AC-9 | History decodes with and without `trashedPieces`. | `historyDecodesWithAndWithoutPieces` |

---

## Data model changes

`CleanupHistoryDeletedItemDTO.trashedPieces: [TrashedPiece]?` (optional, additive). `DeletionReport.DeletedItem.trashedPieces: [TrashedPiece]` (in-memory, `FileDeleter.swift:8-28`).

---

## Known limits

- **Helper-moved items can't be put back.** When an uninstall falls back to the privileged helper (`FileDeleter.applyPrivilegedFallback`, `FileDeleter.swift:390`), the XPC reply (`PurgeHelperProtocol.moveToTrashReportingOwnership`, `purge/PrivilegedHelper/PurgeHelperProtocol.swift:175`) carries only which paths moved, not where they landed, so `recordMoved` stores no pieces (`FileDeleter.swift:418-429`). Those rows show as not restorable. Tracked in [IRD-002](../../../issues/backlog/ird-002-helper-moves-cannot-be-put-back/ird-002-helper-moves-cannot-be-put-back-index.md).
- Restoring an app bundle the helper moved would also need root, which `RestoreService` does not have.
- The Trash location is only as good as what `trashItem` reports; if the user renames or moves the item inside the Trash, it shows "Not in Trash".
- A conflict is all-or-nothing per piece; there is no "keep both" option.

---

## Related

- [PRD-002: Saved folder sizes](../prd-002-saved-folder-sizes/prd-002-saved-folder-sizes-index.md) - restores invalidate cached sizes.
- [IRD-002: Helper moves cannot be put back](../../../issues/backlog/ird-002-helper-moves-cannot-be-put-back/ird-002-helper-moves-cannot-be-put-back-index.md)
- `docs/ROADMAP.md` item 1 ("Put Back") - done.
