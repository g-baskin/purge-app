---
type: decision
title: "Folder-size cache driven by the FSEvents journal, failing toward measuring"
status: accepted
adr_number: 5
decision_date: 2026-10-02
commit_sha: "2f5d327df373b40c823a39262483095912643259"
superseded_by: ""
supersedes: []
created: 2026-10-03
updated: 2026-10-03
tags:
  - decision
  - adr
  - fork-change
related:
  - "[[prd-002-saved-folder-sizes-index|PRD-002]]"
  - "[[ird-001-folder-sizing-deadlock-index|IRD-001]]"
sources:
  - "git:2f5d327"
  - "purge/Utilities/FolderSizeCache.swift"
  - "purge/Utilities/FolderSizing.swift"
---

# ADR-5: Folder-size cache driven by the FSEvents journal, failing toward measuring

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `2f5d327` (2026-10-02). Not present on `upstream-main`.

## Context

Every scan walked every folder with `du` on every launch (commit body). Tracked as [[prd-002-saved-folder-sizes-index|PRD-002]].

## Decision

Folder sizes are saved between launches together with the FSEvents journal position they are good through. Before reuse, the cache replays the journal from that position and re-measures only folders something changed inside. It fails toward measuring: a folder is walked again when the journal was reset, lost events or is too slow to replay; when the size was not checked for 8 hours or measured for about a day; when the folder's inode or change time differs; when the journal reports it under another path; and whenever Purge lacks Full Disk Access. Purge's own deletions and Put Back invalidate affected sizes at once. Stored in `Application Support/io.getpurge.app/folder-size-cache.json`, readable only by the user; off in the test host.

## Alternatives Considered

- **Walk everything every launch (status quo, rejected):** slow (commit body).
- No other alternatives are recorded in the commit or code.

## Consequences

- **Positive:** On an 8-core Mac with 525 folders, first scan 25 s, relaunch 0.9 s (24 walked, 501 reused), every reused size matched a fresh `du` (commit body; not re-measured here).
- **Negative:** Without Full Disk Access the cache is skipped and every folder is measured (`FolderSizeCache.swift:15-17`, `:136`); a file an app keeps open and writing is reported by the journal only when closed, so such changes are caught only by the roughly daily re-measure (`FolderSizeCache.swift:27-31`).
- **Affected entities:** [[FolderSizeCache]], [[FolderSizing]], [[FileDeleter]], [[RestoreService]], [[FolderSizeCacheTests]]
- **Related requirements:** [[prd-002-saved-folder-sizes-index|PRD-002]], [[ird-001-folder-sizing-deadlock-index|IRD-001]]

## Sources

- **Commit:** `2f5d327df373b40c823a39262483095912643259` by AutomationGod on 2026-10-02
- **Message:** "Remember folder sizes and only measure what changed"
- **Body:**
  > Every scan used to walk every folder with du, on every launch. Sizes are
  > now saved between launches with the FSEvents journal position they were
  > measured at. Before reusing them, the cache replays the journal from
  > that position and measures only the folders something changed inside.
  >
  > On an 8-core Mac with 525 cache and app-support folders: the first scan
  > took 25s, a relaunch 0.9s (24 folders walked, 501 reused), and every
  > reused size matched a fresh du.
  >
  > It fails toward measuring. A folder is walked again when the journal
  > was reset, lost events, or is too slow to replay; when the size wasn't
  > checked for 8 hours or measured for about a day; when the folder was
  > replaced or moved (its inode or change time differs); when the journal
  > reports it under another path (symlink, other disk); and whenever Purge
  > lacks Full Disk Access, since hidden folders report no changes. Purge's
  > own deletions and Put Back forget the sizes they affect at once.
  >
  > Saved in Application Support/io.getpurge.app/folder-size-cache.json,
  > readable only by the user. Off in the test host.
- **Code:**
  - `purge/Utilities/FolderSizeCache.swift:4-17 (design summary)`
  - `purge/Utilities/FolderSizeCache.swift:20-39 (limits)`
  - `purge/Utilities/FolderSizeCache.swift:43-47 (off in test host)`
  - `purge/Utilities/FolderSizeCache.swift:136 (FDA gate)`
  - `purge/Utilities/FolderSizing.swift:43,92 (entry points)`
