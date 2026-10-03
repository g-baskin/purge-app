---
type: question
title: "Was fe026b2 (fork branch model) an architectural decision?"
question: "Did commit fe026b2 encode a decision worth filing as an ADR: the fork's main holds its own work, the original project is kept on upstream-main and merged in deliberately, and pushes to the original are disabled?"
answer_quality: draft
created: 2026-10-03
updated: 2026-10-03
status: developing
tags:
  - question
  - adr-candidate
related: []
sources:
  - "git:fe026b2"
  - "README.md"
---

# Was fe026b2 (fork branch model) an architectural decision?

**Question:** Did commit `fe026b2` ("Add steps for pulling the original project's updates into this fork") encode a repository-workflow decision worth filing as an ADR?

## Answer

Unanswered - needs a human call. What the source says:

- `README.md:315-329` ("Updating from the original project"): this fork's `main` "holds your changes"; the original project's code "is kept separately on the `upstream-main` branch, so its updates never land on `main` by themselves"; updates are merged with `git merge --ff-only upstream/main` into `upstream-main`, then `git merge upstream-main` into `main`; "Pushing to the original project is switched off on this machine: `upstream` can only fetch."
- `git remote -v` on this checkout (read 2026-10-03) shows `upstream` push URL `DISABLED-do-not-push-to-original`, consistent with the README. That is local machine config, not versioned in the repo.

Why not filed as an ADR: the commit is a one-line, documentation-only message with no body (the wiki-stinger ADR filter excludes these), and the README describes the arrangement as instructions rather than recording it as a choice among alternatives. The README gives one reason (the original's updates never land on `main` by themselves); it records no alternative (for example rebasing the fork onto upstream, or tracking `upstream/main` directly).

To promote: a human confirms this is a standing policy and, ideally, states why merges were chosen over rebasing.

## Confidence

draft - the arrangement is clearly documented; whether it is an architecture-level decision is not stated.

## Related

- No entity pages: the commit touched only `README.md`, which is outside this run's Swift/shell scope.
