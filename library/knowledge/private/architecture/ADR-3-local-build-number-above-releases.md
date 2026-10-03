---
type: decision
title: "Local builds carry build number 99999 so the updater never replaces them"
status: accepted
adr_number: 3
decision_date: 2026-10-02
commit_sha: "456296e5e13d3b37661253e969d1d4cb28151e72"
superseded_by: ""
supersedes: []
created: 2026-10-03
updated: 2026-10-03
tags:
  - decision
  - adr
  - fork-change
related:
  - "[[prd-003-local-dev-signing-index|PRD-003]]"
sources:
  - "git:456296e"
  - "scripts/dev-sign.sh"
---

# ADR-3: Local builds carry build number 99999 so the updater never replaces them

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `456296e` (2026-10-02). Not present on `upstream-main`.

## Context

Purge ships a built-in updater (Sparkle, `purge/Services/PurgeUpdater.swift:11`). A locally signed build has a different signature from the original author's release (`scripts/dev-sign.sh:4-5`), and being swapped for that release would undo the local build.

## Decision

`scripts/dev-sign.sh` sets `CFBundleVersion` to `99999` (`LOCAL_BUILD_NUMBER`), "Higher than any release's build number, so the updater never offers one".

## Alternatives Considered

- No alternatives are recorded in the commit or code.

## Consequences

- **Positive:** The updater never swaps a local build for an official release.
- **Negative:** None stated in the commit or code.
- **Affected entities:** [[dev-sign]]
- **Related requirements:** [[prd-003-local-dev-signing-index|PRD-003]]

## Sources

- **Commit:** `456296e5e13d3b37661253e969d1d4cb28151e72` by AutomationGod on 2026-10-02
- **Message:** "Add scripts that sign local builds so macOS keeps permissions"
- **Body:**
  > macOS ties Full Disk Access and background-item approval to an app's
  > signature, and every unsigned build gets a new one. dev-signing-setup.sh
  > makes a private certificate once; dev-run.sh and dev-test.sh build, sign
  > every program in the app with it, and set a very high build number so
  > the updater never swaps a local build for a release.
  >
  > Signed builds run without the hardened runtime: with it on, macOS only
  > loads libraries from the same Apple developer team, and a private
  > certificate has none.
- **Code:**
  - `scripts/dev-sign.sh:4-5 (purpose)`
  - `scripts/dev-sign.sh:20-21 (LOCAL_BUILD_NUMBER=99999)`
  - `scripts/dev-sign.sh:58 (plutil sets CFBundleVersion)`
