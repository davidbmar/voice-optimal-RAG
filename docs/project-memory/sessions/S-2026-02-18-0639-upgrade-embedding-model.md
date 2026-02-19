# Session

Session-ID: S-2026-02-18-0639-upgrade-embedding-model
Title: Upgrade RAG embedding model to nomic-embed-text-v1.5
Date: 2026-02-18
Author: Claude

## Goal

Replace `all-MiniLM-L6-v2` (384-dim) with `nomic-ai/nomic-embed-text-v1.5` (768-dim) to improve retrieval quality, especially for code/technical content. Add task prefix support and auto-migration for dimension changes.

## Context

The current embedding model produces low relevance scores (0.43-0.46) and is weak on code/technical content. The nightly cron already does full re-indexing, so this is a clean swap. On startup, the vector store will detect the dimension mismatch and recreate the table.

## Plan

1. Update `config.py` — new default model + task prefix config
2. Update `embedder.py` — trust_remote_code + task prefixes
3. Update `vector_store.py` — dynamic schema + auto-migration
4. Update `Dockerfile` + `docker-compose.yml` — new model name
5. Update `README.md` — reflect new model

## Changes Made

- `config.py`: Default model → `nomic-ai/nomic-embed-text-v1.5`, added `TASK_PREFIX_MODELS` dict with substring-matched `(query_prefix, doc_prefix)` tuples
- `embedder.py`: Added `trust_remote_code=True` to constructor, `_get_task_prefixes()` helper, query prefix in `embed_text()`, doc prefix in `embed_batch()`
- `vector_store.py`: Replaced hard-coded 384-dim `SCHEMA` with `_build_schema(dim)`, added dimension mismatch detection in `init_store()` that drops and recreates the table
- `Dockerfile`: Updated model download and `ENV EMBEDDING_MODEL` to new model
- `docker-compose.yml`: Updated `EMBEDDING_MODEL` env var
- `README.md`: Updated model name, dimension (384→768), and technical decisions table
- `requirements.txt`: Added `einops>=0.8.0` — required by nomic's custom model code, not a transitive dep of sentence-transformers

## Decisions Made

- **Substring matching for task prefixes**: Used substring matching (`"nomic-embed-text"` in model name) rather than exact match so it handles org-prefix variations and version bumps
- **Auto-migration via drop+recreate**: On dimension mismatch, drop the existing table and create a new one. Safe because nightly cron does full re-index
- **trust_remote_code=True for all models**: Harmless for models that don't need it, required by nomic

## Open Questions

None — plan is well-defined.

## Links

Commits:
- (to be added)

PRs:
- (to be added)

ADRs:
- None needed — model swap is a straightforward upgrade
