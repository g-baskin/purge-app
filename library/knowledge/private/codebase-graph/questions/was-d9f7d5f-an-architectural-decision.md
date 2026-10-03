---
type: question
title: "Was d9f7d5f (Put Back) an architectural decision?"
question: "Did commit d9f7d5f encode architectural decisions worth filing as ADRs, beyond the feature requirements already recorded in PRD-001?"
answer_quality: draft
created: 2026-10-03
updated: 2026-10-03
status: developing
tags:
  - question
  - adr-candidate
related:
  - "[[prd-001-put-back-index]]"
  - "[[ird-002-helper-moves-cannot-be-put-back-index]]"
sources:
  - "git:d9f7d5f"
  - "purge/Services/RestoreService.swift"
---

# Was d9f7d5f (Put Back) an architectural decision?

**Question:** Did commit `d9f7d5f` ("Add Put Back: restore cleaned items from Cleanup History") encode architectural decisions worth filing as ADRs, or are its rules feature requirements that belong only in [[prd-001-put-back-index|PRD-001]]?

## Answer

Unanswered - needs a human call. The commit body states three rules that read like design constraints:

1. Moving an item to the Trash records where it landed (`TrashedPiece`, `purge/Models/CleanupHistoryEntry.swift:10-24`).
2. Put Back "never overwrites anything at the original location, only restores from a Trash folder into the home folder or an Applications folder" (`purge/Services/RestoreService.swift:114-138`).
3. It "treats history files as untrusted" (`RestoreService.isAcceptable`, `purge/Services/RestoreService.swift:114-127`).

Why not filed as an ADR: the message is a feature description with no decision or rationale language (no "instead of", no rejected alternative, no stated reason for choosing these rules over others), and all three rules are already captured as goals in [[prd-001-put-back-index|PRD-001]]. The commit also records a known limit ("Items moved by the privileged helper aren't recorded yet"), tracked as [[ird-002-helper-moves-cannot-be-put-back-index|IRD-002]].

To promote: a human confirms that "history is untrusted input" and/or "never overwrite on restore" are standing rules other features must follow, and states why.

## Confidence

draft - the rules are stated; whether they are architecture-level decisions is a judgement the commit text does not make.

## Related

- [[RestoreService]], [[CleanupHistoryEntry]], [[CleanupHistoryStore]], [[FileDeleter]], [[CleanupHistoryDetailView]], [[RestoreServiceTests]]
