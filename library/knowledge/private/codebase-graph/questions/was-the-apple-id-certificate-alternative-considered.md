---
type: question
title: "Why a private certificate rather than an Apple ID certificate?"
question: "Why were local builds signed with a private self-signed certificate rather than a (free) Apple ID development certificate, which has a team and could keep the hardened runtime on?"
answer_quality: draft
created: 2026-10-03
updated: 2026-10-03
status: developing
tags:
  - question
  - rationale-gap
related:
  - "[[ADR-2-sign-local-builds-with-private-certificate]]"
  - "[[ADR-4-local-builds-without-hardened-runtime]]"
  - "[[prd-003-local-dev-signing-index]]"
sources:
  - "git:456296e"
  - "scripts/dev-sign.sh"
---

# Why a private certificate rather than an Apple ID certificate?

**Question:** [[ADR-2-sign-local-builds-with-private-certificate|ADR-2]] and [[ADR-4-local-builds-without-hardened-runtime|ADR-4]] record that local builds use a private self-signed certificate and therefore run without the hardened runtime. Why was an Apple ID certificate not used instead?

## Answer

Unanswered. The only mention of the alternative is the comment at `scripts/dev-sign.sh:99`: "A certificate from an Apple ID has a team, so it could keep the protection on." Neither commit `456296e` nor the README section "Keep permissions between builds" (`README.md:283-294`) says why that option was not taken. This page exists so the ADRs do not invent a reason.

A human who knows the reason (for example: not wanting to sign in with an Apple ID, or keeping setup scriptable) should add it to ADR-2's "Alternatives Considered".

## Confidence

draft - rationale gap; no source states the reason.

## Related

- [[dev-sign]], [[dev-signing-setup]]
