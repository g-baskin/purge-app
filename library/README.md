---
ai_description: |
  This is the root of the repository's documentation library (schema v2).
  You own everything under library/ except notes/, which is human-only.
  Sub-trees: knowledge/ (public and private docs), requirements/ (product
  work: PRDs), issues/ (reactive bug/incident work: IRDs), notes/ (junk
  drawer, read-only to agents).
  Schema v2 is described inline here and in each sub-folder's README
  frontmatter (ai_description / human_description).
human_description: |
  Root of this repository's documentation library.
  - knowledge/: reference documentation split by audience (public vs private)
  - requirements/: planned product work (PRDs) with backlog/in-work/completed lifecycle
  - issues/: reactive bug and incident work (IRDs) with same lifecycle
  - notes/: unstructured scratch space - only humans write here
  Each sub-folder carries a README explaining what belongs in it.
---

# Library

Documentation library for **Purge**: a native macOS app (Swift / SwiftUI) that cleans caches, developer-tool junk and large files, and uninstalls apps. Purge moves everything to the Trash and never deletes outright. This repository is [g-baskin/purge-app](https://github.com/g-baskin/purge-app), a fork of [jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app), at version 1.7.0.

Xcode targets: `purge` (the app), `PurgeHelper` (root launchd daemon `io.getpurge.helper`, registered with SMAppService and reached over XPC), `PurgeWatch` (agent `io.getpurge.watch`), and `PurgeTests` (Swift Testing). The fork owner is `g-baskin`.

Other repository docs: [`README.md`](../README.md), [`CONTRIBUTING.md`](../CONTRIBUTING.md), [`SECURITY.md`](../SECURITY.md), [`docs/design-system.md`](../docs/design-system.md), [`docs/ROADMAP.md`](../docs/ROADMAP.md) (superseded by the backlog PRDs in `requirements/backlog/`).

Documentation root for this repository. Schema version: **v2**.

The schema is self-describing: this README plus each sub-folder's `README.md` (which carry `ai_description` / `human_description` frontmatter) define what belongs where. Start at the sub-folder READMEs for the per-tree invariants.

## Top-level layout

| Folder | What goes here |
|---|---|
| `knowledge/public/` | End-user / customer-facing docs: overviews, guides, FAQs |
| `knowledge/private/` | Internal engineering and business docs: ADRs, standards, domain knowledge |
| `requirements/` | Product and feature work: PRDs in backlog/in-work/completed |
| `issues/` | Reactive bug and incident work: IRDs in backlog/in-work/completed |
| `notes/` | Human-only scratch space |

## What does NOT belong here

- Binary assets (images, fonts, PDFs) -> an `assets/` or `public/` folder outside `library/`
- Generated source code or build output -> stays in the source tree, never mirrored here
- Wiki entity pages authored by `wiki-worker-bee` DO belong here, under `knowledge/` - they are not a separate mirror
