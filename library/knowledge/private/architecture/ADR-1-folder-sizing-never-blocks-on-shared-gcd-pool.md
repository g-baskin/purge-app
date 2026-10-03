---
type: decision
title: "Folder sizing never blocks on GCD's shared pool"
status: accepted
adr_number: 1
decision_date: 2026-10-02
commit_sha: "80d10c1e438e8e9d129caf60d2ab8a306de2aeb0"
superseded_by: ""
supersedes: []
created: 2026-10-03
updated: 2026-10-03
tags:
  - decision
  - adr
  - fork-change
related:
  - "[[ird-001-folder-sizing-deadlock-index|IRD-001]]"
  - "[[prd-002-saved-folder-sizes-index|PRD-002]]"
sources:
  - "git:80d10c1"
  - "purge/Utilities/FolderSizing.swift"
  - "PurgeTests/FolderSizingConcurrencyTests.swift"
---

# ADR-1: Folder sizing never blocks on GCD's shared pool

> [!note] Filing basis
> This repository does not use Conventional Commits, so no fork commit matches the wiki-stinger Tier-1 regex catalog. This ADR was filed on the orchestrator-confirmed criterion: the decision and its reason are stated in plain prose in the commit message and/or a code comment, quoted under Sources. Nothing here goes beyond that text and the cited code. Filed by direct invocation (`partial_scan: true`); the number was assigned in commit order, not by a graph driver.

## Status

Accepted - shipped on the fork's `main` in commit `80d10c1` (2026-10-02). Not present on `upstream-main`.

## Context

`FolderSizing.directorySizes` blocked its caller on a `DispatchGroup` while `du` ran on GCD's global queue. Scans call it from many threads at once; once the blocked callers held every worker thread, none was left to run the work and every call hung (seen with eight concurrent callers on an 8-core Mac). Tracked as [[ird-001-folder-sizing-deadlock-index|IRD-001]].

## Decision

A single chunk of folders is measured inline on the calling thread. Several chunks each run on a `Thread` started just for them, at most one per `duChunkLimiter` permit (`maxConcurrentDuChunks = 10`), so folder sizing never depends on GCD's shared pool while its caller is blocked.

## Alternatives Considered

- **Previous design (rejected):** dispatch chunks to `DispatchQueue.global(qos: .utility)` and wait on a `DispatchGroup`; rejected because it starves the pool and hangs (commit body).
- No other alternatives are recorded in the commit or code.

## Consequences

- **Positive:** Any number of concurrent callers complete; the commit reports a sixteen-caller check finishing in under a second where the old code hung. Two tests run twice as many concurrent callers as the Mac has cores.
- **Negative:** None stated in the commit or code.
- **Affected entities:** [[FolderSizing]], [[FolderSizingConcurrencyTests]]
- **Related requirements:** [[ird-001-folder-sizing-deadlock-index|IRD-001]], [[prd-002-saved-folder-sizes-index|PRD-002]]

## Sources

- **Commit:** `80d10c1e438e8e9d129caf60d2ab8a306de2aeb0` by AutomationGod on 2026-10-02
- **Message:** "Fix folder sizing hanging when many measurements run at once"
- **Body:**
  > FolderSizing.directorySizes blocked its caller on a DispatchGroup while
  > du ran on GCD's global queue. Scans call it from many threads at once,
  > and once the blocked callers held every worker thread there was none
  > left to run the work: every call hung forever. Seen on an 8-core Mac,
  > where eight concurrent callers were enough. A standalone check with
  > sixteen callers hung with the old code and finished in under a second
  > with the new.
  >
  > A single chunk now runs on the calling thread. Several run on threads
  > started just for them, at most one per limiter permit, so they never
  > depend on the shared pool. Two new tests run twice as many concurrent
  > callers as the Mac has cores, for single- and multi-chunk calls.
- **Code:**
  - `purge/Utilities/FolderSizing.swift:105-113 (rationale comment, inline single chunk)`
  - `purge/Utilities/FolderSizing.swift:131-132 (dedicated Thread per permit)`
  - `purge/Utilities/FolderSizing.swift:8,17 (maxConcurrentDuChunks, duChunkLimiter)`
  - `PurgeTests/FolderSizingConcurrencyTests.swift:199,218 (concurrency tests)`
