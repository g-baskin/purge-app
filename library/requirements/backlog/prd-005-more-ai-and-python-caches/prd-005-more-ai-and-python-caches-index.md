# PRD-005: More Developer and AI Caches (Hugging Face, pip, uv, conda)

> **Status:** Backlog
> **Priority:** P2
> **Effort:** S (1-3h)
> **Schema changes:** None
> **Source:** `docs/ROADMAP.md` item 4, remainder. Bun, Deno, Android and Playwright are already done upstream (`purge/Services/DevScanner.swift`, e.g. lines 425-426, 520).

---

## Overview

Add the remaining developer/AI caches as `DevScanner` entries, each with an explanation and safety label. No code for Hugging Face, pip, uv or conda exists in `purge/` today (grep, October 2026).

All items follow the roadmap's guiding rules: Trash by default (nothing new deletes permanently); every new item gets a `SafetyLevel` and new categories start at `medium` ("Check First") until proven; new paths go through `DeletionSafetyPolicy` and anything not explicitly allowed is skipped; every new category gets an `ExplanationDatabase` entry; tests in `PurgeTests/` use temp directories, never the real home folder.

---

## Goals

| Cache | Path | Label |
|---|---|---|
| Hugging Face | `~/.cache/huggingface` | `medium` (models can be large to re-download) |
| pip | `~/Library/Caches/pip` | `safe` |
| uv | `~/.cache/uv` | `safe` |
| conda | the `pkgs` cache of a found conda install (e.g. `~/miniconda3/pkgs`, `~/anaconda3/pkgs`, `~/miniforge3/pkgs`) | `safe` |

## Non-Goals

- Deleting conda environments, virtualenvs, or Hugging Face model files outside the cache.
- Running `pip cache purge` / `uv cache clean` / `conda clean` (Purge moves folders to the Trash).

---

## Acceptance criteria

| ID | Criterion |
|---|---|
| AC-1 | Given a fake home containing each path, when `DevScanner` runs, then each cache is found with the label above and a size. |
| AC-2 | Each path is added to the `DeletionSafetyPolicy` allowlist and nothing broader (e.g. `~/.cache` itself stays refused). |
| AC-3 | Each entry has an `explanations.json` key mapped in `DevScanner.toolExplanationKeys`. |
| AC-4 | For conda, only `pkgs` is offered; `envs` is never offered (tested). |

---

## Implementation notes

- `purge/Services/DevScanner.swift` (tool list around lines 400-530, `toolExplanationKeys` lines 22-55), `purge/Services/DeletionSafetyPolicy.swift`, `purge/Resources/explanations.json`.
- Should Hugging Face live in `AIModelScanner` next to Ollama / LM Studio instead of `DevScanner`?

---

## Open questions

- [ ] Does `CacheScanner` already surface `~/Library/Caches/pip` generically as an app cache? If so, avoid double listing.
- [ ] Respect `HF_HOME`, `UV_CACHE_DIR`, `PIP_CACHE_DIR` when set? (Environment of a GUI app may differ from the shell.)

---

## Related

- `docs/ROADMAP.md` item 4
