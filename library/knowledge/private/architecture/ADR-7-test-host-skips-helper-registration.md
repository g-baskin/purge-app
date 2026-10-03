---
type: decision
title: "The test host does not re-register the privileged helper"
status: accepted
adr_number: 7
decision_date: 2026-10-02
commit_sha: "d9a5e7e28e5fe4ef624923cddb009c75499cb831"
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
  - "git:d9a5e7e"
  - "purge/Services/AppBootstrapper.swift"
---

# ADR-7: The test host does not re-register the privileged helper

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `d9a5e7e` (2026-10-02). Not present on `upstream-main`.

## Context

The test host is a second copy of Purge.app; registering the root helper from it could move the approved helper over to the test copy (commit body; `purge/Services/AppBootstrapper.swift:43-45`).

## Decision

`AppBootstrapper` returns before `PrivilegedHelperManager.reconcileVersion()` when `TestHost.isActive()`.

## Alternatives Considered

- No alternatives are recorded in the commit or code.

## Consequences

- **Positive:** Running tests no longer disturbs the helper approved for the user's real copy of Purge.
- **Negative:** None stated in the commit; as a direct effect of the guard, launch-time helper reconciliation does not run under tests.
- **Affected entities:** [[AppBootstrapper]]
- **Related requirements:** [[prd-003-local-dev-signing-index|PRD-003]]

## Sources

- **Commit:** `d9a5e7e28e5fe4ef624923cddb009c75499cb831` by AutomationGod on 2026-10-02
- **Message:** "Let the uninstall helper trust a local build's own certificate"
- **Body:**
  > The helper and the app only trusted code signed by the original
  > developer's team, so a build signed with a private certificate could
  > never remove admin-installed apps: the helper refused every request.
  >
  > A local build now records its certificate's SHA-1 fingerprint in its
  > Info.plist (scripts/dev-sign.sh writes it, and the signature seals it).
  > Both ends add exactly that one certificate to the team requirement.
  > Release builds never carry the key, so they keep the original,
  > team-only requirement with no "or" clause; tests read a release-shaped
  > Info.plist to pin that, and malformed values are ignored rather than
  > spliced into the requirement.
  >
  > The test host no longer re-registers the helper at launch: it is a
  > second copy of Purge.app, and registering from it could move the
  > approved helper over to the test copy.
- **Code:**
  - `purge/Services/AppBootstrapper.swift:41-51`
