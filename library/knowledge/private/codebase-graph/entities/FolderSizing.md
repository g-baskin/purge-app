---
type: entity
title: "FolderSizing"
entity_type: module
status: stub
created: "2026-10-03"
updated: "2026-10-03"
path: "purge/Utilities/FolderSizing.swift"
language: swift
source_extension: ".swift"
last_commit_hash: "2f5d327df373b40c823a39262483095912643259"
depends_on: []
used_by: []
tags:
  - entity
  - stub
  - fork-change
related: []
sources:
  - "purge/Utilities/FolderSizing.swift"
---

# FolderSizing

> [!gap]
> This file is in a language with no wired tree-sitter grammar (`swift`).
> A stub page has been filed so the knowledge area acknowledges its existence and incoming wikilinks remain valid.
> Adding a tree-sitter grammar for this language will upgrade this page in place.

## Source

`purge/Utilities/FolderSizing.swift` (173 lines; present on `upstream-main`, modified by the fork) - last touched in commit `2f5d327` (AutomationGod, 2026-10-02).

Fork commits touching it (`git log upstream-main..main -- purge/Utilities/FolderSizing.swift`):
  - `2f5d327` - Remember folder sizes and only measure what changed (2026-10-02)
  - `80d10c1` - Fix folder sizing hanging when many measurements run at once (2026-10-02)

## Covered by

- [[ird-001-folder-sizing-deadlock-index|IRD-001 Folder sizing deadlock]]
- [[prd-002-saved-folder-sizes-index|PRD-002 Saved Folder Sizes]]
- [[ADR-1-folder-sizing-never-blocks-on-shared-gcd-pool|ADR-1]]
- [[ADR-5-folder-size-cache-driven-by-fsevents-journal|ADR-5]]
