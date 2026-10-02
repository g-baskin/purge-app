# Purge Roadmap: Next Features

Status: proposal, not yet scheduled. Ordered by suggested build order (value vs. effort, and how much existing code each one reuses).

**Progress (2 October 2026, after updating to the original project's 1.7.0 code):**

- Done: 1 (Put Back).
- Done upstream: 2 (App Uninstaller and leftovers from deleted apps, plus a helper that removes admin-locked apps), and much of 6 (the Overview tab breaks down the whole disk, though not as a zoomable chart).
- Partly done upstream: 4 already covers Bun, Deno, Android and Playwright caches. Hugging Face, pip, uv and conda are still missing.
- Still open: 3 (upstream deliberately never touches iPhone backups, so treat that part with care), 5, 7, 8, 9.

Guiding rules that apply to every item:

- **Trash by default.** Nothing new deletes permanently.
- **Safety labels first.** Every new item gets a `SafetyLevel` (`safe` / `medium` / `unknown`). New categories start at `medium` ("Check First") until proven.
- **Refuse by default.** New paths go through `DeletionSafetyPolicy`; anything not explicitly allowed is skipped.
- **Explain in plain English.** Every new category gets an `ExplanationDatabase` entry.
- **Tests with every feature** in `PurgeTests/`, using temp directories, never the real home folder.

---

## 1. Undo a cleanup ("Put Back")

**Why:** Makes cleaning feel risk-free. Cheapest big trust win.
**Effort:** Small (1–2 days).

**Current gap:** `FileDeleter` calls `FileManager.trashItem(at:resultingItemURL: nil)`, so the item's location in the Trash is thrown away. `CleanupHistoryDeletedItemDTO` only stores the original `path`.

**Plan:**
1. Capture `resultingItemURL` in all three `trashItem` call sites in `FileDeleter`.
2. Add optional `trashedPath: String?` to `DeletedItem` and `CleanupHistoryDeletedItemDTO` (optional, so old history still decodes).
3. New `RestoreService`: for each item, check the trashed copy still exists and the original path is free; move it back with `FileManager.moveItem`. Never overwrite — report a conflict instead.
4. `CleanupHistoryDetailView`: "Put Back All" and per-row "Put Back"; disable rows whose Trash copy is gone (Trash emptied).
5. Simulator deletions via `simctl` cannot be restored — mark them as not restorable.

**Done when:** a cleaned item can be restored from history; emptied-Trash and name-conflict cases show a clear message; tests cover all three.

---

## 2. App Uninstaller + Leftover Finder

**Why:** The headline feature of the most popular peers (Pearcleaner, PureMac). Fills Purge's biggest gap.
**Effort:** Large (4–7 days).

**Two modes:**
- **Uninstall an app:** pick or drag in an `.app`, show the app plus related files, move all to Trash.
- **Leftovers:** files belonging to bundle IDs of apps no longer installed.

**Plan:**
1. New `InstalledAppIndex`: read `/Applications`, `~/Applications` and their bundle IDs/names from each `Info.plist`.
2. New `AppFootprintScanner`: for a bundle ID + name, look in the standard places:
   - `~/Library/Application Support/<name|bundleID>`
   - `~/Library/Caches/<bundleID>`, `~/Library/HTTPStorages/<bundleID>`
   - `~/Library/Preferences/<bundleID>.plist`, `ByHost` prefs
   - `~/Library/Containers/<bundleID>`, `~/Library/Group Containers/*<teamID|bundleID>*`
   - `~/Library/Saved Application State/<bundleID>.savedState`
   - `~/Library/LaunchAgents/*<bundleID>*`, `~/Library/Logs/<name>`, `~/Library/WebKit/<bundleID>`
3. Matching confidence: an exact bundle-ID match is `safe`; a name-only match is `medium`; any Apple (`com.apple.*`) or shared item is refused (reuse `isProtectedContainerBundleID`).
4. Refuse to uninstall running apps, Apple apps, and apps in `/System`.
5. System-wide items (`/Library/LaunchDaemons`, privileged helpers) are **listed only**, with "needs admin" text — no privilege escalation in v1.
6. UI: new sidebar mode "Apps" (reuse `ScanListRow`, brand icons, `DeletionConfirmSheet`), plus a drag-and-drop target.

**Done when:** uninstalling a test app removes its bundle and matched files to Trash; leftovers from a deleted test app are found; Apple apps can't be selected.

---

## 3. iPhone/iPad Backups and iOS Update Files

**Why:** Often 10–100 GB, invisible to most users.
**Effort:** Small (1–2 days).

**Plan:**
1. Scan `~/Library/Application Support/MobileSync/Backup/*`. Read `Info.plist` per backup for device name and last backup date.
2. Scan `~/Library/iTunes/iPhone Software Updates` and `iPad Software Updates` for `.ipsw` files.
3. Labels: `.ipsw` = `safe` (re-downloadable). Backups = `medium` ("Check First") — show device name + date; never part of "Clean Safe Items" or scheduled cleaning.
4. Show in General mode as a new group, with an explanation entry.

**Done when:** backups show device name and date, are excluded from one-click and scheduled cleaning, and `.ipsw` files are cleanable.

---

## 4. More Developer and AI Caches

**Why:** Purge already scans Ollama, LM Studio and Go caches; extending is cheap.
**Effort:** Small (1–2 days).

**Add (each as a `DevScanner` entry with explanation and safety label):**
- Hugging Face: `~/.cache/huggingface` (`medium` — models can be large to re-download)
- pip `~/Library/Caches/pip`, uv `~/.cache/uv`, conda `pkgs` cache (`safe`)
- Bun `~/.bun/install/cache`, Deno cache (`safe`)
- Android SDK system images and AVDs (`medium`)
- Playwright/Puppeteer browser downloads `~/Library/Caches/ms-playwright` (`safe`)

**Done when:** each path is found in tests with a fake home folder, and appears with the right label.

---

## 5. Duplicate File Finder

**Why:** Common request; reuses the Large Files folders and UI.
**Effort:** Medium (3–4 days).

**Plan:**
1. Same folders and exclusions as `LargeFileScanPolicy`; minimum size 1 MB by default.
2. Three-stage match to stay fast: group by exact size → hash the first 64 KB → full SHA-256 only for the remaining candidates (CryptoKit, streamed in chunks).
3. Skip hard links and clones (compare file IDs) so "duplicates" that share disk space aren't shown as savings.
4. UI: groups with "keep newest / keep oldest / keep in folder X" helpers; one copy per group is always kept and can't be selected.
5. Label `medium`; never in one-click or scheduled cleaning.

**Done when:** test fixtures with duplicates, near-duplicates and hard links give correct groups; the app can never select every copy in a group.

---

## 6. Disk Map (Sunburst Chart)

**Why:** Shows *where* space goes; strong for screenshots and README.
**Effort:** Medium (3–5 days).

**Plan:**
1. Folder size tree built in the background with `FolderSizing`, with depth limit and cancellation.
2. Sunburst drawn with SwiftUI `Canvas` (no new dependency); click to zoom in, breadcrumb to zoom out.
3. Read-only in v1 except "Reveal in Finder" and "Show in Large Files".
4. Must stay smooth: aggregate small slices into "Other", cap drawn segments.

**Done when:** scanning the home folder stays responsive, can be cancelled, and the chart matches Finder sizes within a reasonable margin.

---

## 7. Time Machine Local Snapshots

**Why:** A hidden source of "System Data".
**Effort:** Small–Medium (2 days).

**Plan:** list via `tmutil listlocalsnapshots /` (through `ProcessRunner`), show dates; offer `tmutil thinlocalsnapshots` with clear text. Label `medium`. Note: sizes are not reliably reported — show count and dates, not fake byte numbers.

---

## 8. Low-Disk Warning (Menu Bar)

**Effort:** Small (1 day). Use `VolumeCapacityReader`; notify once when free space drops below a user-set level (default 10%), with a "Review safe items" action. Rate-limited to once a day.

---

## 9. Command-Line Tool

**Effort:** Medium (3–4 days). `purge scan` / `purge clean --safe` sharing the same scanners and `DeletionSafetyPolicy`. Requires moving scanners into a shared framework target first, so do this last.

---

## Suggested Order

| # | Feature | Effort | Reuses |
|---|---------|--------|--------|
| 1 | Undo / Put Back | S | History, FileDeleter |
| 2 | App Uninstaller + Leftovers | L | Scanners, brand icons, confirm sheet |
| 3 | iOS backups & updates | S | General mode groups |
| 4 | More dev/AI caches | S | DevScanner, AIModelScanner |
| 5 | Duplicate finder | M | Large Files policy and UI |
| 6 | Disk map | M | FolderSizing |
| 7 | Time Machine snapshots | S–M | ProcessRunner |
| 8 | Low-disk warning | S | VolumeCapacityReader, notifier |
| 9 | CLI | M | Needs shared framework |
