# Session

Session-ID: S-2026-02-18-0549-rag-tool-integration
Title: Add RAG Tool to Voice Assistant
Date: 2026-02-18
Author: Claude

## Goal

Connect the RAG service (running on localhost:8100 with 690 indexed GitHub repo docs) to the voice assistant by adding a `RAGTool` that the LLM can call to answer questions about the user's projects.

## Context

- RAG service is live on port 8100 with documents from all of davidbmar's GitHub repos
- Voice assistant has a tool-calling framework with `BaseTool`, explicit registration in `__init__.py`, and `httpx` already in dependencies
- The `WebSearchTool` provides the pattern to follow

## Plan

1. Create `voice_assistant/tools/rag.py` — new `RAGTool` class following the `WebSearchTool` pattern
2. Modify `voice_assistant/tools/__init__.py` — import and register the new tool
3. Modify `voice_assistant/config.py` — add `rag_url` setting

## Changes Made

- Created `voice_assistant/tools/rag.py` with `RAGTool` class
  - POSTs to `/query` endpoint with `{"query": ..., "top_k": 5}`
  - Formats results as numbered list with repo name, relevance score, and text snippet
  - 2-second timeout, graceful failure if RAG service is down
  - URL configurable via `RAG_URL` env var (default: `http://localhost:8100`)
- Modified `voice_assistant/tools/__init__.py` — added import and `register_tool(RAGTool)`
- Modified `voice_assistant/config.py` — added `rag_url` field to both Settings variants

## Decisions Made

- Tool name `search_knowledge_base` chosen to distinguish from `web_search` — the LLM needs a clear signal about when to use each tool
- `top_k=5` as default — balances providing enough context without overwhelming the LLM's response
- 2-second timeout — RAG is local so should be fast; don't block the voice pipeline
- `document_id` used as repo identifier in output — the RAG service stores repo names as document IDs

## Open Questions

None.

## Links

Commits:
- (pending)
