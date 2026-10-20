<!-- gg:init:start -->
# Purge — personal macOS fork

Native SwiftUI/AppKit storage cleaner for caches, developer artifacts, large files, app leftovers, Downloads and local Docker Desktop resources. This is an Xcode app, not the Python project described by inherited context; npm only supports icons and design-token tooling.

Read CONTEXT.md before naming anything.

## Architecture that matters

- `PurgeStore` coordinates queued scans and cleanup. Docker and Downloads have independent review models; Downloads uses `FileDeleter`, while Docker uses Engine API object deletion rather than filesystem removal.
- Long-lived models belong to `AppEnvironment`; `AppBootstrapper` wires services from the app delegate, not window appearance. Login/menu-bar and removed-app launches can be windowless, so window-scoped bootstrap leaves services inactive.
- `FirstRunGate.resolve()` must precede writes to user defaults: it distinguishes upgrades from fresh installs using prior persisted state. Startup-mode repair follows the gate, before Dock/window decisions.
- The app and root helper compile the shared `purge/PrivilegedHelper/PurgeHelperProtocol.swift`. Bump `PurgeHelperConstants.version` when helper behavior changes; reconciliation uses that independent version to replace a surviving daemon.

## Gotchas / invariants

- **Only the pinned personal copy runs normally.** `PersonalCopyLock` requires `/Users/dellcbyerllc/projects/purge-app/build/dev/Build/Products/Debug/Purge.app` and its pinned certificate; violations exit 78 before app state initializes. `dev-run.sh` also rejects other checkout paths, including feature worktrees. Recreating a certificate does not satisfy the existing pin. Upstream Sparkle updates are deliberately disabled to prevent replacement by a differently signed binary.
- **Limited scans must check `ProtectedLocations` before metadata reads or path normalization.** Even `standardizedFileURL`, `fileExists` and symlink resolution can reach TCC-protected targets and prompt or hang. Preserve component-wise `readlink` handling, including symlink-plus-`..` semantics and Apple media-cache exclusions (`ScanAccess.swift`). Full Disk Access grants interrupt limited scans and prioritize replacement results; scheduled cleanup holds the scan queue to avoid competing walks.
- **Subprocess drains cannot depend on the cooperative thread pool.** `ProcessRunner` drains both pipes with calling-thread `poll` off-main and escalates SIGTERM to SIGKILL. Waiting before draining fills pipes; scheduling drain workers on the same saturated pool deadlocks concurrent scans.
- **Folder sizes require journal evidence, not folder timestamps.** `FolderSizeCache` bypasses caching without Full Disk Access and captures identity/journal watermark before measurement so mid-walk changes remain visible. Invalidate ancestors and descendants after local mutations; FSEvents delivery can lag.
- **Protection is enforced at mutation, not merely selection.** Unreadable/corrupt `DeletionProtection` storage blocks deletion. Locks cover ancestors and descendants; authentication grants cover specific record IDs for five minutes without removing locks. Background cleanup cannot authenticate; any file lock gates whole-Trash emptying.
- **Docker cleanup stays local and object-specific.** Only the user's Docker Desktop Unix socket is accepted. Revalidate daemon identity and resource revision before deleting; volume names can be reused. No forced deletion, bulk prune, container-volume removal or build-cache deletion. `FileDeleter` rejects Docker VM disks/container storage rather than treating them as ordinary large files.
- **Age does not prove a Git worktree is disposable.** `GitWorktreeRegistration` treats unreadable metadata, unplugged volumes and moved-but-repairable paths as unknown. Compare registration by file identity and recheck proven orphanhood immediately before Trash.
- **Moved bytes are not reclaimed bytes.** Cleanup reports/history retain pending Trash bytes separately from measured volume delta; unknown reclaimed space stays unknown. Legacy `totalFreedBytes` decodes into moved bytes only. Put Back requires recorded Trash destinations, which privileged-helper moves currently do not provide.

## Local workflows and release traps

- Personal launch: `scripts/dev-run.sh` builds, signs and opens the canonical copy; `--no-open` builds/signs only. Signing readiness is checked before building. Initial `scripts/dev-signing-setup.sh` changes user keychain/trust state, not just build files. Stable signing preserves macOS permission identity; `dev-sign.sh` seals helper trust metadata and signs nested programs before the outer bundle. Its private certificate requires hardened runtime off.
- Hosted tests: `scripts/dev-test.sh` performs build-for-testing then serial test-without-building in `build/test`. It uses a separate bundle ID/URL scheme and no private certificate; optional `-only-testing:PurgeTests/RestoreServiceTests` reaches the execution stage. Preserve isolation and the `TestHost` guards: registering the helper from tests can redirect the approved daemon to the test copy. Cases share one `NSApplication`, hence serial execution. Build CI does not execute these tests.
- Xcode's brand-icon phase suppresses generator failures into warnings, and the generator succeeds with partially missing slugs. A successful app build therefore does not prove icon generation completed; inspect generator output for icon changes.
- `scripts/make-dmg.sh <version> [app-path]` consumes an already exported, signed app; it does not build/export one. Embedded version must match. Notarize and staple before calculating Sparkle signature/length because stapling changes the DMG. This and the release-triggered Homebrew workflow retain upstream identities/destinations; the latter writes to `jithin-sabu/homebrew-tap`, not this fork. The referenced `release.sh` is absent, so publishing is not a complete checked-in workflow.
<!-- gg:init:end -->
