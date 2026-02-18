# Session

Session-ID: S-2026-02-18-0340-initial-build
Title: Initial RAG service build — project scaffolding and full implementation
Date: 2026-02-18
Author: Claude + David

## Goal

Build the complete RAG service from the design doc: FastAPI server with document ingestion, vector search, drag-and-drop UI, and Docker packaging.

## Context

New standalone project for voice assistant RAG retrieval. Design doc approved at `docs/plans/2026-02-17-rag-service-design.md`. Traceable project memory system integrated from template repo.

## Plan

1. Set up project scaffolding (config, models, CLAUDE.md, project memory)
2. Implement core modules: embedder, vector store, parsers, chunker
3. Wire up document pipeline
4. Build FastAPI app with all routes
5. Create drag-and-drop web UI
6. Add Dockerfile and docker-compose.yml
7. Test end-to-end

## Changes Made

- Initialized git repo with project memory system
- Created design doc and implementation plan
- `config.py` — 11 env vars with defaults
- `models.py` — 10 Pydantic request/response schemas
- `chunker.py` — recursive character text splitter with tiktoken token counting
- `parsers.py` — file parsers for PDF (PyMuPDF), DOCX, Markdown, HTML (BeautifulSoup), TXT
- `embedder.py` — sentence-transformers wrapper with batch support (all-MiniLM-L6-v2, 384-dim)
- `vector_store.py` — LanceDB operations (insert, search, delete, list, stats) using PyArrow directly
- `document_pipeline.py` — orchestrator: parse → chunk → embed → store
- `app.py` — FastAPI app with 6 routes (/, /upload, /documents, /documents/{id}, /query, /health)
- `static/index.html` — drag-and-drop web UI, dark theme, document management, search test
- `Dockerfile` — Python 3.13-slim, pre-downloads model at build time
- `docker-compose.yml` — single-service setup with named volume
- `requirements.txt` — 11 dependencies pinned to actual latest versions
- 11 unit tests (5 chunker, 6 parsers) — all passing

## Decisions Made

- Used actual latest pip versions instead of spec's future versions. Pinned: fastapi==0.128.8, lancedb==0.27.1, sentence-transformers==5.1.2, etc.
- Used PyArrow directly in vector_store.py instead of pandas — avoids adding pandas as a dependency
- Score calculation uses `1/(1+distance)` instead of `1-distance` — more robust for non-normalized L2 distances
- Web UI uses safe DOM methods (textContent/createElement) instead of innerHTML for XSS prevention
- Used Python 3.13 venv for local dev (PEP 668 enforced on macOS)
- Integrated traceable-searchable-adr-memory-index for session/decision tracking

## Open Questions

- Query latency ~57ms warm (higher than spec's 20-30ms target) — could improve with cosine distance metric or index tuning
- Dockerfile not yet tested with `docker build` (tested local server only)

## Links

Commits:
- `9cb30db` Add config and Pydantic models
- `cbb1a27` Add recursive text chunker with tiktoken token counting
- `c4ee295` Add file parsers for PDF, DOCX, MD, HTML, TXT
- `077aaa3` Add embedding model wrapper with batch support
- `1702c97` Add LanceDB vector store with insert, search, delete, list
- `f64affd` Add document ingestion pipeline: parse, chunk, embed, store
- `2356b14` Add FastAPI app with all API routes
- `06ee7ea` Add drag-and-drop web UI for document management and search testing
- `fa8679c` Add Docker configuration

PRs:
- (none yet)

ADRs:
- (none yet — technology choices documented in design doc)
