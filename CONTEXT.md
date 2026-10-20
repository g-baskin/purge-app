**Cleanup**: The umbrella term for removing selected storage items. File cleanup normally moves items to Trash; direct removal, Empty Trash and Docker object removal are distinct operations with different recovery options.

**Move to Trash**: Relocate a file or folder to Trash rather than permanently removing it. Its bytes still occupy storage, and recovery depends on the trashed copy remaining available.

**Empty Trash**: Permanently remove items already in Trash. It is not another name for ordinary file cleanup, and Put Back cannot recover emptied items.

**Direct removal**: Remove an item without sending it to Trash, such as deleting a simulator through its owning tool. It is not eligible for Put Back.

**Docker object removal**: Permanently remove an explicitly selected local Docker image, container or volume. It does not use Trash, does not force removal and preserves container volumes. Build cache is review-only.

**Put Back**: Return a recorded trashed item to its original location when the trashed copy remains available and the destination is free. It never overwrites an existing item and is not a general undo for permanent removal.

**Bytes moved to Trash**: The sum of file sizes successfully moved during cleanup. These bytes are pending in Trash, not a measurement of space reclaimed on the volume. Avoid: calling this total freed or reclaimed space.

**Reclaimed space**: A measured change in a volume's available capacity, not a sum of selected file sizes. Only a reportable increase may be presented as reclaimed space; missing or inconclusive measurements remain unknown, not zero. Avoid: reclaimed or freed for estimates or bytes merely moved to Trash.

**Cleaning History**: Recorded manual or scheduled file-cleanup sessions, including moved-byte totals, removed and skipped items, and any reportable reclaimed-space measurement. A history record alone does not guarantee that an item can be put back.

**Safe to Clean**: The lower-risk classification eligible for safe automatic cleanup. It does not override exclusions, protected-item locks or permission checks.

**Check First**: The review-required risk classification for an eligible scan result. It is not part of safe automatic cleanup.

**Not Sure**: The fallback classification for an unidentified folder, not a third risk tier. Such items do not surface in classified scan results.

**Excluded from scans**: A user-selected file or folder that scans skip, including an excluded folder's descendants. Exclusion narrows scan coverage; it is not an authenticated protected-item lock.

**Protected item**: A file, folder, app bundle or Docker resource locked against cleanup inside Purge. Folder protection also blocks deleting a containing parent. This is distinct from a location guarded by macOS privacy permissions and does not constrain other programs.

**Protection grant**: Temporary authenticated approval for specific protected items, expiring after five minutes without removing their locks. Background cleanup does not request authentication.

**Full Disk Access**: The macOS privacy permission allowing broader scan coverage. It is distinct from approval to clean a protected item and does not bypass that item's lock.

**Limited scan**: Scanning without Full Disk Access while avoiding macOS privacy-protected locations and their symlink targets. Missing results in this mode do not establish that those locations are empty.
