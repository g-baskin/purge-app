---
type: decision
title: "Local builds are signed without the hardened runtime"
status: accepted
adr_number: 4
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
  - "README.md"
---

# ADR-4: Local builds are signed without the hardened runtime

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `456296e` (2026-10-02). Not present on `upstream-main`.

## Context

With the hardened runtime on, library validation lets an app load only libraries signed by the same Apple developer team. The private certificate from [[ADR-2-sign-local-builds-with-private-certificate|ADR-2]] has no team, so the app could not load its own libraries and would not start (`scripts/dev-sign.sh:96-99`).

## Decision

`scripts/dev-sign.sh` signs with `codesign --force --sign <fingerprint> --timestamp=none --preserve-metadata=identifier,entitlements` and deliberately omits `--options runtime`, so locally signed builds run without the hardened runtime.

## Alternatives Considered

- **Keep the hardened runtime with a teamed certificate (Apple ID):** named in `scripts/dev-sign.sh:99` as able to keep the protection on; not chosen, reason not stated (see [[was-the-apple-id-certificate-alternative-considered]]).

## Consequences

- **Positive:** Locally signed builds launch and load their own frameworks.
- **Negative:** Local builds lose the hardened runtime's protections; the README tells users to set this up only on their own Mac. Release builds are not affected by this script.
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
  - `scripts/dev-sign.sh:95-102 (sign function and rationale comment)`
  - `README.md:294 (risk note)`
