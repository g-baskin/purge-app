---
type: decision
title: "Privileged helper trusts one local certificate sealed in the build's Info.plist"
status: accepted
adr_number: 6
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
  - "purge/PrivilegedHelper/PurgeHelperProtocol.swift"
  - "PurgeHelper/HelperListenerDelegate.swift"
  - "purge/PrivilegedHelper/PrivilegedHelperManager.swift"
  - "scripts/dev-sign.sh"
  - "PurgeTests/PrivilegedHelperRequirementTests.swift"
---

# ADR-6: Privileged helper trusts one local certificate sealed in the build's Info.plist

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `d9a5e7e` (2026-10-02). Not present on `upstream-main`.

## Context

The helper and the app only trusted code signed by the original developer's team (`BX83ZBV95B`), so a build signed with the private certificate of [[ADR-2-sign-local-builds-with-private-certificate|ADR-2]] could never remove admin-installed apps: the helper refused every request (commit body).

## Decision

A local build records its certificate's SHA-1 in `PurgeLocalSigningCertificateSHA1` in its `Info.plist` (written by `scripts/dev-sign.sh`, sealed by the signature). Both ends OR exactly that one certificate into the team requirement. Release builds never carry the key and keep the team-only requirement with no "or" clause. Malformed values are ignored rather than spliced in, and tests pin the release-shaped result.

## Alternatives Considered

- No alternatives are recorded in the commit or code.

## Consequences

- **Positive:** Local builds can use the helper; release trust is unchanged.
- **Negative:** A local build's helper also accepts anything signed by that private certificate, which other programs running as the user can use ([[ADR-2-sign-local-builds-with-private-certificate|ADR-2]]).
- **Affected entities:** [[PurgeHelperProtocol]], [[dev-sign]], [[PrivilegedHelperRequirementTests]]
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
  - `purge/PrivilegedHelper/PurgeHelperProtocol.swift:42-64 (key and requirement)`
  - `purge/PrivilegedHelper/PurgeHelperProtocol.swift:66-74 (validatedFingerprint)`
  - `purge/PrivilegedHelper/PurgeHelperProtocol.swift:32,38 (clientRequirement, helperRequirement)`
  - `PurgeHelper/HelperListenerDelegate.swift:18`
  - `purge/PrivilegedHelper/PrivilegedHelperManager.swift:87`
  - `scripts/dev-sign.sh:59-60`
  - `PurgeTests/PrivilegedHelperRequirementTests.swift:37,89`
