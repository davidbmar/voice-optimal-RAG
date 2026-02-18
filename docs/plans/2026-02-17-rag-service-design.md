# RAG Service — Design Document

## Purpose

A self-contained Docker service that provides document ingestion (drag-and-drop web UI) and real-time vector retrieval for a voice assistant. The voice assistant's engine calls this service's query API to retrieve relevant context before sending prompts to the LLM.

This service is a new standalone component. It does NOT modify the existing voice assistant repo (`iphone-webrtc-TURN-speaker-streaming-machost-iphonebrowser`). The voice assistant calls this service over HTTP.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Docker Container (rag-service)          Port 8100      │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  FastAPI Server                                   │  │
│  │                                                   │  │
│  │  Routes:                                          │  │
│  │    GET  /              → Drag-and-drop web UI     │  │
│  │    POST /upload        → Accept + ingest docs     │  │
│  │    GET  /documents     → List indexed documents   │  │
│  │    DELETE /documents/{id} → Remove doc + vectors  │  │
│  │    POST /query         → Vector search            │  │
│  │    GET  /health        → Status + stats           │  │
│  └──────────┬────────────────────────┬───────────────┘  │
│             │                        │                   │
│  ┌──────────▼──────────┐  ┌─────────▼────────────────┐  │
│  │  Document Pipeline  │  │  Query Pipeline           │  │
│  │                     │  │                           │  │
│  │  Parse (PDF/MD/TXT) │  │  Embed query (~10ms)     │  │
│  │  Chunk (recursive)  │  │  Vector search (~5-15ms)  │  │
│  │  Embed (batch)      │  │  Return top-k chunks     │  │
│  │  Store in LanceDB   │  │                           │  │
│  └─────────────────────┘  └───────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Storage (mounted volume: /data)                  │  │
│  │    /data/lancedb/    → Vector index               │  │
│  │    /data/uploads/    → Original uploaded files     │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Embedding Model (loaded at startup)              │  │
│  │    Default: all-MiniLM-L6-v2 (~80MB)              │  │
│  │    Configurable via EMBEDDING_MODEL env var        │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Integration With Voice Assistant

The voice assistant's agent loop changes from:

```
STT text → LLM → TTS
```

To:

```
STT text → POST http://rag-service:8100/query → inject context into LLM prompt → LLM → TTS
```

The query call adds ~15-30ms to the pipeline. The voice assistant repo needs a small addition to `engine/llm.py` to call the RAG service before building the LLM prompt. That integration is NOT part of this service.

---

## Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Vector DB** | LanceDB (embedded) | No server process, Rust-based, fast, stores in a directory |
| **Embedding model** | `all-MiniLM-L6-v2` (sentence-transformers) | ~80MB, ~10ms per query on CPU, battle-tested. Swappable via env var |
| **Web framework** | FastAPI + uvicorn | Async, fast, auto-generates OpenAPI docs at `/docs` |
| **Document parsing** | PyMuPDF (PDF), python-docx (DOCX), markdown lib, plain text | Covers common document types |
| **Chunking** | Recursive character splitter | ~500 tokens per chunk, ~50 token overlap |
| **Token counting** | tiktoken (`cl100k_base`) | Accurate token counts for chunk sizing |
| **Container** | Docker, single container | Simple. LanceDB is embedded, model is in-process |

---

## API Specification

### POST /upload

Upload one or more files for ingestion.

**Request:** `multipart/form-data` with one or more files.

**Supported file types:** `.pdf`, `.md`, `.txt`, `.docx`, `.html`

**Response:**
```json
{
  "documents": [
    {
      "id": "doc_a1b2c3d4",
      "filename": "company-handbook.pdf",
      "chunks": 47,
      "status": "indexed"
    }
  ]
}
```

### GET /documents

List all indexed documents.

**Response:**
```json
{
  "documents": [
    {
      "id": "doc_a1b2c3d4",
      "filename": "company-handbook.pdf",
      "chunks": 47,
      "indexed_at": "2025-02-17T10:30:00Z",
      "file_size_bytes": 245000
    }
  ]
}
```

### DELETE /documents/{id}

Remove a document and all its vectors from the index.

**Response:**
```json
{
  "id": "doc_a1b2c3d4",
  "deleted": true,
  "chunks_removed": 47
}
```

### POST /query

Retrieve relevant chunks for a query string.

**Request:**
```json
{
  "query": "what is the vacation policy",
  "top_k": 5
}
```

**Response:**
```json
{
  "query": "what is the vacation policy",
  "results": [
    {
      "text": "Employees receive 15 days of paid vacation per year...",
      "score": 0.87,
      "document_id": "doc_a1b2c3d4",
      "filename": "company-handbook.pdf",
      "chunk_index": 12
    }
  ],
  "query_time_ms": 18
}
```

### GET /health

**Response:**
```json
{
  "status": "healthy",
  "documents": 3,
  "total_chunks": 142,
  "embedding_model": "all-MiniLM-L6-v2",
  "uptime_seconds": 3600
}
```

---

## File Structure

```
rag-service/
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/
│   ├── plans/
│   │   └── 2026-02-17-rag-service-design.md   # This file
│   └── project-memory/
│       ├── .index/
│       ├── adr/
│       ├── backlog/
│       ├── sessions/
│       ├── architecture/
│       ├── runbooks/
│       └── index.md
├── scripts/
│   ├── build-index.sh
│   ├── setup-hooks.sh
│   └── test.sh
├── tests/
│   └── test-index-builder.sh
├── CLAUDE.md
├── Dockerfile
├── requirements.txt
├── app.py
├── config.py
├── document_pipeline.py
├── parsers.py
├── chunker.py
├── embedder.py
├── vector_store.py
├── models.py
├── static/
│   └── index.html
└── docker-compose.yml
```

---

## Dependencies (Latest Versions, Feb 2026)

```
fastapi==0.129.0
uvicorn[standard]==0.41.0
python-multipart==0.0.22
sentence-transformers==5.2.3
lancedb==0.29.2
pyarrow==23.0.1
pymupdf==1.27.1
python-docx==1.2.0
beautifulsoup4==4.14.3
markdown==3.10.2
tiktoken==0.12.0
```

Note: These versions were the latest available as of 2026-02-17. Pinned for reproducibility.

---

## Document Pipeline Detail

### Parsing

- **PDF** (`PyMuPDF`): Extract text per page. Preserve page boundaries as metadata.
- **DOCX** (`python-docx`): Extract paragraph text. Preserve heading structure.
- **Markdown**: Convert to plain text, strip formatting but preserve structure.
- **HTML** (`BeautifulSoup`): Extract visible text, strip tags.
- **TXT**: Read as-is.

### Chunking

Recursive character splitter:

- **Target chunk size:** 500 tokens (~2000 characters)
- **Chunk overlap:** 50 tokens (~200 characters)
- **Split hierarchy:** `\n\n` → `\n` → `. ` → ` ` → character
- **Token counter:** tiktoken `cl100k_base`

### Embedding

- Load `SentenceTransformer(EMBEDDING_MODEL)` once at startup
- Batch-embed all chunks per document
- For queries, embed single string
- Model configurable via `EMBEDDING_MODEL` env var

### Storage (LanceDB)

Single table `chunks`:

| Column | Type | Description |
|--------|------|-------------|
| `id` | string | `{document_id}_{chunk_index}` |
| `document_id` | string | Parent document ID |
| `filename` | string | Original filename |
| `chunk_index` | int | Position in document |
| `text` | string | Chunk content |
| `vector` | float32[384] | Embedding (384 dims for MiniLM) |
| `page_number` | int (nullable) | Source page if available |
| `indexed_at` | string | ISO timestamp |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8100` | Server listen port |
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | sentence-transformers model name |
| `LANCEDB_PATH` | `/data/lancedb` | Path to LanceDB storage directory |
| `UPLOAD_PATH` | `/data/uploads` | Path to store original uploaded files |
| `CHUNK_SIZE` | `500` | Target chunk size in tokens |
| `CHUNK_OVERLAP` | `50` | Overlap between chunks in tokens |
| `MAX_UPLOAD_SIZE_MB` | `50` | Maximum file upload size |
| `TOP_K_DEFAULT` | `5` | Default number of results for /query |
| `LOG_LEVEL` | `info` | Logging level |

---

## Performance Expectations

| Operation | Expected Latency |
|-----------|-------------------|
| Embed single query | ~10ms |
| Vector search (top-5) | ~5-15ms |
| **Total query round-trip** | **~20-30ms** |
| Full ingest: 10-page PDF | ~500ms-1s |

---

## Future Enhancements (Not in v1)

1. Hybrid search (vector + BM25)
2. Cross-encoder re-ranking
3. Streaming ingestion (directory watch)
4. Semantic chunking
5. Multi-tenancy
6. Authentication
7. Embedding model upgrade
8. GPU acceleration
9. OCR support
10. Web scraping
