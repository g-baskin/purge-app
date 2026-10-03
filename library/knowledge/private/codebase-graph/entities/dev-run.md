---
type: entity
title: "dev-run"
entity_type: module
status: stub
created: "2026-10-03"
updated: "2026-10-03"
path: "scripts/dev-run.sh"
language: shell
source_extension: ".sh"
last_commit_hash: "456296e5e13d3b37661253e969d1d4cb28151e72"
depends_on: []
used_by: []
tags:
  - entity
  - stub
  - fork-change
related: []
sources:
  - "scripts/dev-run.sh"
---

# dev-run

> [!gap]
> This file is in a language with no wired tree-sitter grammar (`shell`).
> A stub page has been filed so the knowledge area acknowledges its existence and incoming wikilinks remain valid.
> Adding a tree-sitter grammar for this language will upgrade this page in place.

## Source

`scripts/dev-run.sh` (77 lines; added by the fork) - last touched in commit `456296e` (AutomationGod, 2026-10-02).

Fork commits touching it (`git log upstream-main..main -- scripts/dev-run.sh`):
  - `456296e` - Add scripts that sign local builds so macOS keeps permissions (2026-10-02)

## Covered by

- [[prd-003-local-dev-signing-index|PRD-003 Local Development Signing]]
- [[ADR-2-sign-local-builds-with-private-certificate|ADR-2]]
