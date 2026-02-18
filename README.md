# RAG Service

Self-contained document retrieval service. Upload files (PDF, Markdown, TXT, DOCX, HTML), get semantic vector search back. Runs as a single Docker container with no external dependencies.

Built to feed context into a [voice assistant](https://github.com/davidbmar/iphone-webrtc-TURN-speaker-streaming-machost-iphonebrowser) — speak a question, RAG fetches the relevant chunks, LLM answers with grounded context.

## How It Works

```
Upload file  →  Parse text  →  Split into chunks  →  Embed (384-dim vectors)  →  Store in LanceDB
                                                                                       │
Query "which projects use WebRTC?"  →  Embed query  →  Vector similarity search  ──────┘
                                                              │
                                                        Top-K results with scores
```

## Quick Start

### Docker (recommended)

```bash
docker build -t rag-service .
docker run -d --name rag-service -p 8100:8100 -v rag-data:/data rag-service
open http://localhost:8100
```

### Local (development)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app:app --host 0.0.0.0 --port 8100
```

## Web UI

Open `http://localhost:8100` for a drag-and-drop interface:

- **Upload zone** — drag files or click to browse (PDF, MD, TXT, DOCX, HTML)
- **Document list** — see all indexed documents with chunk counts, delete individually
- **Search box** — type a natural language query, see ranked results with similarity scores

## API

### `POST /upload`

Upload one or more files for ingestion.

```bash
curl -X POST http://localhost:8100/upload -F "files=@document.pdf"
```

```json
{
  "documents": [
    {"id": "doc_a1b2c3d4", "filename": "document.pdf", "chunks": 12, "status": "indexed"}
  ]
}
```

### `POST /query`

Semantic search across all indexed documents.

```bash
curl -X POST http://localhost:8100/query \
  -H "Content-Type: application/json" \
  -d '{"query": "which projects handle WebRTC?", "top_k": 5}'
```

```json
{
  "query": "which projects handle WebRTC?",
  "results": [
    {"text": "Voice agent running on a Mac host...", "score": 0.5663, "document_id": "doc_0e14bae2", "filename": "iphone-webrtc/README.md", "chunk_index": 0}
  ],
  "query_time_ms": 61.0
}
```

### `GET /documents`

List all indexed documents.

### `DELETE /documents/{doc_id}`

Remove a document and all its chunks.

### `GET /health`

```json
{
  "status": "healthy",
  "documents": 690,
  "total_chunks": 2988,
  "embedding_model": "all-MiniLM-L6-v2",
  "uptime_seconds": 134.6
}
```

## Nightly GitHub Indexing

Index all `.md` files across every repo in a GitHub account:

```bash
# Manual run
bash scripts/index-github-repos.sh

# Cron is pre-configured to run at 2 AM daily
# Check logs after a run:
cat /tmp/rag-nightly-index.log
```

The cron wrapper (`scripts/nightly-index-cron.sh`) starts Docker and the container if they're not running.

Requires: `gh` CLI authenticated (`gh auth login`).

## Project Structure

```
├── app.py                  # FastAPI routes (upload, query, documents, health)
├── document_pipeline.py    # Orchestrator: parse → chunk → embed → store
├── parsers.py              # File parsers (PDF, MD, TXT, DOCX, HTML)
├── chunker.py              # Recursive text splitter (tiktoken token counting)
├── embedder.py             # sentence-transformers wrapper (all-MiniLM-L6-v2)
├── vector_store.py         # LanceDB operations (insert, search, delete, stats)
├── models.py               # Pydantic request/response schemas
├── config.py               # Environment variables with defaults
├── static/index.html       # Web UI (drag-and-drop upload, search, doc management)
├── Dockerfile              # Single container, model pre-downloaded at build
├── requirements.txt        # Pinned dependencies
├── tests/
│   ├── test_chunker.py     # Chunker unit tests
│   ├── test_parsers.py     # Parser unit tests
│   └── fixtures/           # Test files (sample.txt, sample.md, sample.html)
└── scripts/
    ├── index-github-repos.sh   # Clone all repos, upload .md files to RAG
    ├── nightly-index-cron.sh   # Cron wrapper (starts Docker, runs indexer, logs)
    ├── build-index.sh          # Project memory index builder
    └── setup-hooks.sh          # Git pre-commit hook installer
```

## Configuration

All settings via environment variables (see `config.py`):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8100` | Server port |
| `EMBEDDING_MODEL` | `all-MiniLM-L6-v2` | Sentence-transformers model |
| `LANCEDB_PATH` | `./data/lancedb` | Vector database directory |
| `UPLOAD_PATH` | `./data/uploads` | Uploaded file storage |
| `CHUNK_SIZE` | `500` | Target tokens per chunk |
| `CHUNK_OVERLAP` | `50` | Overlap tokens between chunks |
| `MAX_UPLOAD_SIZE_MB` | `50` | Max upload file size |
| `TOP_K_DEFAULT` | `5` | Default search results count |
| `LOG_LEVEL` | `info` | Logging level |

## Technical Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Embedding model | all-MiniLM-L6-v2 | 384-dim, fast, good quality, runs on CPU |
| Vector DB | LanceDB | Embedded (no server process), stores in a directory, zero ops |
| Text splitting | Recursive character splitter | Preserves paragraph/sentence boundaries, tiktoken token counting |
| PDF parsing | PyMuPDF | Fast, page-level metadata, no Java dependency |
| Score formula | `1/(1+distance)` | Converts L2 distance to 0-1 similarity score |
| Container | Single Dockerfile | Model pre-downloaded at build for instant startup |
| Data persistence | Docker volume at `/data` | Survives container restarts |

## Tests

```bash
source .venv/bin/activate
pytest tests/ -v
```
