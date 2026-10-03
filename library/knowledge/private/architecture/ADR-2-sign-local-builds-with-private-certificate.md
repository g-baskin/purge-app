---
type: decision
title: "Sign local builds with a private self-signed certificate"
status: accepted
adr_number: 2
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
  - "scripts/dev-signing-setup.sh"
  - "scripts/dev-sign.sh"
  - "README.md"
---

# ADR-2: Sign local builds with a private self-signed certificate

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `456296e` (2026-10-02). Not present on `upstream-main`.

## Context

macOS ties Full Disk Access and background-item approval to an app's signature, and every unsigned (ad-hoc) build gets a new one, so each local build had to be granted permissions again (commit body; `scripts/dev-signing-setup.sh:7-9`).

## Decision

Local builds are signed with a private certificate, "Purge Local Development", created once by `scripts/dev-signing-setup.sh` in its own keychain and trusted for code signing for the current user only. `scripts/dev-run.sh` and `scripts/dev-test.sh` build and then call `scripts/dev-sign.sh`, which signs every program in the app with it, inside-out, including the extra executables in `Contents/MacOS`, and fails if the resulting designated requirement names a `cdhash` instead of the certificate.

## Alternatives Considered

- **Ad-hoc signing (status quo, rejected):** a new signature per build, so permissions reset (commit body).
- **Certificate from an Apple ID:** mentioned only in `scripts/dev-sign.sh:99` (it has a team, so it could keep the hardened runtime on). Why the private certificate was preferred over it is **not stated** in the commit or code; see [[was-the-apple-id-certificate-alternative-considered]].

## Consequences

- **Positive:** macOS sees every local build as the same app, so permissions persist across rebuilds.
- **Negative:** The certificate's keychain is unlocked by builds without asking, so other programs running as the user could sign code with it (`scripts/dev-signing-setup.sh:15-17`; README "Keep permissions between builds"). Requires turning off the hardened runtime ([[ADR-4-local-builds-without-hardened-runtime|ADR-4]]) and an explicit helper trust rule ([[ADR-6-helper-trusts-one-local-certificate|ADR-6]]).
- **Affected entities:** [[dev-signing-setup]], [[dev-sign]], [[dev-run]], [[dev-test]]
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
  - `scripts/dev-signing-setup.sh:1-21 (purpose, risk statement)`
  - `scripts/dev-sign.sh:100-101 (codesign with the private certificate)`
  - `scripts/dev-sign.sh:126-135 (reject cdhash requirement)`
  - `README.md:283-294 (Keep permissions between builds)`
