---
type: entity
title: "dev-sign"
entity_type: module
status: stub
created: "2026-10-03"
updated: "2026-10-03"
path: "scripts/dev-sign.sh"
language: shell
source_extension: ".sh"
last_commit_hash: "d9a5e7e28e5fe4ef624923cddb009c75499cb831"
depends_on: []
used_by: []
tags:
  - entity
  - stub
  - fork-change
related: []
sources:
  - "scripts/dev-sign.sh"
---

# dev-sign

> [!gap]
> This file is in a language with no wired tree-sitter grammar (`shell`).
> A stub page has been filed so the knowledge area acknowledges its existence and incoming wikilinks remain valid.
> Adding a tree-sitter grammar for this language will upgrade this page in place.

## Source

`scripts/dev-sign.sh` (135 lines; added by the fork) - last touched in commit `d9a5e7e` (AutomationGod, 2026-10-02).

Fork commits touching it (`git log upstream-main..main -- scripts/dev-sign.sh`):
  - `d9a5e7e` - Let the uninstall helper trust a local build's own certificate (2026-10-02)
  - `456296e` - Add scripts that sign local builds so macOS keeps permissions (2026-10-02)

## Covered by

- [[prd-003-local-dev-signing-index|PRD-003 Local Development Signing]]
- [[ADR-2-sign-local-builds-with-private-certificate|ADR-2]]
- [[ADR-3-local-build-number-above-releases|ADR-3]]
- [[ADR-4-local-builds-without-hardened-runtime|ADR-4]]
- [[ADR-6-helper-trusts-one-local-certificate|ADR-6]]
- [[was-the-apple-id-certificate-alternative-considered|Question: why not an Apple ID certificate?]]
