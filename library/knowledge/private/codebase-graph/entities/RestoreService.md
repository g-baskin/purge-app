---
type: entity
title: "RestoreService"
entity_type: module
status: stub
created: "2026-10-03"
updated: "2026-10-03"
path: "purge/Services/RestoreService.swift"
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
  - "purge/Services/RestoreService.swift"
---

# RestoreService

> [!gap]
> This file is in a language with no wired tree-sitter grammar (`swift`).
> A stub page has been filed so the knowledge area acknowledges its existence and incoming wikilinks remain valid.
> Adding a tree-sitter grammar for this language will upgrade this page in place.

## Source

`purge/Services/RestoreService.swift` (150 lines; added by the fork) - last touched in commit `2f5d327` (AutomationGod, 2026-10-02).

Fork commits touching it (`git log upstream-main..main -- purge/Services/RestoreService.swift`):
  - `2f5d327` - Remember folder sizes and only measure what changed (2026-10-02)
  - `d9f7d5f` - Add Put Back: restore cleaned items from Cleanup History (2026-10-02)

## Covered by

- [[prd-001-put-back-index|PRD-001 Put Back]]
- [[prd-002-saved-folder-sizes-index|PRD-002 Saved Folder Sizes]]
- [[ird-002-helper-moves-cannot-be-put-back-index|IRD-002 Helper moves can't be put back]]
- [[ADR-5-folder-size-cache-driven-by-fsevents-journal|ADR-5]]
- [[was-d9f7d5f-an-architectural-decision|Question: was d9f7d5f an ADR?]]
