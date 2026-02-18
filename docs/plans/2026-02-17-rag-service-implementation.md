# RAG Service Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a self-contained Docker service with document ingestion, vector search, and drag-and-drop web UI for voice assistant RAG retrieval.

**Architecture:** FastAPI server with embedded LanceDB vector store and in-process sentence-transformers embedding model. Single Docker container on port 8100. Parse → Chunk → Embed → Store pipeline for ingestion; Embed → Search for queries.

**Tech Stack:** FastAPI, LanceDB 0.29.2, sentence-transformers 5.2.3, PyMuPDF, python-docx, tiktoken, Docker

**Session:** S-2026-02-18-0340-initial-build

---

### Task 1: Config + Pydantic Models (Foundation)

**Files:**
- Create: `config.py`
- Create: `models.py`
- Create: `requirements.txt`

**Step 1: Create requirements.txt**

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

**Step 2: Create config.py**

All env vars with defaults. Single source of truth for configuration.

```python
import os

PORT = int(os.getenv("PORT", "8100"))
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "all-MiniLM-L6-v2")
LANCEDB_PATH = os.getenv("LANCEDB_PATH", "./data/lancedb")
UPLOAD_PATH = os.getenv("UPLOAD_PATH", "./data/uploads")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "500"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "50"))
MAX_UPLOAD_SIZE_MB = int(os.getenv("MAX_UPLOAD_SIZE_MB", "50"))
TOP_K_DEFAULT = int(os.getenv("TOP_K_DEFAULT", "5"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

SUPPORTED_EXTENSIONS = {".pdf", ".md", ".txt", ".docx", ".html"}
```

**Step 3: Create models.py**

Pydantic request/response models matching the API spec exactly.

```python
from pydantic import BaseModel, Field
from typing import Optional


class QueryRequest(BaseModel):
    query: str
    top_k: int = Field(default=5, ge=1, le=50)


class QueryResult(BaseModel):
    text: str
    score: float
    document_id: str
    filename: str
    chunk_index: int


class QueryResponse(BaseModel):
    query: str
    results: list[QueryResult]
    query_time_ms: float


class DocumentInfo(BaseModel):
    id: str
    filename: str
    chunks: int
    indexed_at: str
    file_size_bytes: int


class UploadedDocumentInfo(BaseModel):
    id: str
    filename: str
    chunks: int
    status: str = "indexed"


class UploadResponse(BaseModel):
    documents: list[UploadedDocumentInfo]


class DocumentListResponse(BaseModel):
    documents: list[DocumentInfo]


class DeleteResponse(BaseModel):
    id: str
    deleted: bool
    chunks_removed: int


class HealthResponse(BaseModel):
    status: str
    documents: int
    total_chunks: int
    embedding_model: str
    uptime_seconds: float
```

**Step 4: Install dependencies**

Run: `pip install -r requirements.txt`

**Step 5: Verify imports**

Run: `python -c "from config import *; from models import *; print('OK')"`
Expected: `OK`

**Step 6: Commit**

```bash
git add requirements.txt config.py models.py
git commit -m "Add config and Pydantic models

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 2: Chunker (Pure Logic — TDD)

**Files:**
- Create: `chunker.py`
- Create: `tests/test_chunker.py`

This is pure logic with no external dependencies beyond tiktoken. Perfect for TDD.

**Step 1: Write failing tests**

```python
import pytest
from chunker import chunk_text


def test_short_text_single_chunk():
    """Text shorter than chunk_size stays as one chunk."""
    text = "Hello world. This is a short text."
    chunks = chunk_text(text, chunk_size=500, chunk_overlap=50)
    assert len(chunks) == 1
    assert chunks[0] == text


def test_splits_on_double_newline():
    """Prefers splitting on paragraph boundaries."""
    para1 = "First paragraph. " * 50  # ~150 tokens
    para2 = "Second paragraph. " * 50
    text = para1.strip() + "\n\n" + para2.strip()
    chunks = chunk_text(text, chunk_size=200, chunk_overlap=20)
    assert len(chunks) >= 2
    assert "First paragraph" in chunks[0]
    assert "Second paragraph" in chunks[-1]


def test_overlap_between_chunks():
    """Adjacent chunks should share overlapping content."""
    # Create text that will definitely need multiple chunks
    text = " ".join(f"sentence{i} word word word word." for i in range(200))
    chunks = chunk_text(text, chunk_size=100, chunk_overlap=20)
    assert len(chunks) >= 2
    # Check that the end of chunk 0 appears at the start of chunk 1
    # (overlap means some content is shared)
    last_words_chunk0 = chunks[0].split()[-5:]
    first_words_chunk1 = chunks[1].split()[:20]
    overlap = set(last_words_chunk0) & set(first_words_chunk1)
    assert len(overlap) > 0, "Chunks should have overlapping content"


def test_empty_text():
    """Empty text returns empty list."""
    assert chunk_text("", chunk_size=500, chunk_overlap=50) == []


def test_whitespace_only():
    """Whitespace-only text returns empty list."""
    assert chunk_text("   \n\n  ", chunk_size=500, chunk_overlap=50) == []
```

**Step 2: Run tests to verify they fail**

Run: `python -m pytest tests/test_chunker.py -v`
Expected: FAIL (chunker module not found)

**Step 3: Implement chunker.py**

Recursive character text splitter using tiktoken for token counting.

```python
import tiktoken

_encoder = tiktoken.get_encoding("cl100k_base")


def _token_count(text: str) -> int:
    return len(_encoder.encode(text))


def chunk_text(
    text: str,
    chunk_size: int = 500,
    chunk_overlap: int = 50,
    separators: list[str] | None = None,
) -> list[str]:
    """Split text into chunks of approximately chunk_size tokens with overlap."""
    text = text.strip()
    if not text:
        return []

    if _token_count(text) <= chunk_size:
        return [text]

    if separators is None:
        separators = ["\n\n", "\n", ". ", " ", ""]

    return _recursive_split(text, separators, chunk_size, chunk_overlap)


def _recursive_split(
    text: str,
    separators: list[str],
    chunk_size: int,
    chunk_overlap: int,
) -> list[str]:
    """Recursively split text using separator hierarchy."""
    sep = separators[0]
    remaining_seps = separators[1:]

    # Split on current separator
    if sep == "":
        pieces = list(text)
    else:
        pieces = text.split(sep)

    # Merge pieces into chunks that fit within chunk_size
    chunks = []
    current = ""

    for piece in pieces:
        candidate = (current + sep + piece).strip() if current else piece.strip()

        if _token_count(candidate) <= chunk_size:
            current = candidate
        else:
            if current:
                chunks.append(current)
            # If the piece itself is too big, split it with next separator
            if _token_count(piece.strip()) > chunk_size and remaining_seps:
                sub_chunks = _recursive_split(
                    piece.strip(), remaining_seps, chunk_size, chunk_overlap
                )
                chunks.extend(sub_chunks)
                current = ""
            else:
                current = piece.strip()

    if current:
        chunks.append(current)

    # Apply overlap: prepend tail of previous chunk to each subsequent chunk
    if chunk_overlap > 0 and len(chunks) > 1:
        chunks = _apply_overlap(chunks, chunk_overlap)

    return chunks


def _apply_overlap(chunks: list[str], overlap_tokens: int) -> list[str]:
    """Add overlap by prepending the tail of each chunk to the next."""
    result = [chunks[0]]
    for i in range(1, len(chunks)):
        prev_tokens = _encoder.encode(chunks[i - 1])
        overlap_text = _encoder.decode(prev_tokens[-overlap_tokens:])
        merged = (overlap_text + " " + chunks[i]).strip()
        result.append(merged)
    return result
```

**Step 4: Run tests to verify they pass**

Run: `python -m pytest tests/test_chunker.py -v`
Expected: All PASS

**Step 5: Commit**

```bash
git add chunker.py tests/test_chunker.py
git commit -m "Add recursive text chunker with tiktoken token counting

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 3: Parsers (File Type Extraction)

**Files:**
- Create: `parsers.py`
- Create: `tests/test_parsers.py`
- Create: `tests/fixtures/` (test files)

**Step 1: Create test fixtures**

Create small test files for each supported format:
- `tests/fixtures/sample.txt` — plain text
- `tests/fixtures/sample.md` — markdown with formatting
- `tests/fixtures/sample.html` — HTML with tags

(PDF and DOCX fixtures are binary — create them programmatically in tests.)

**Step 2: Write failing tests**

```python
import pytest
import os
from parsers import parse_file

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def test_parse_txt():
    path = os.path.join(FIXTURES, "sample.txt")
    result = parse_file(path)
    assert result["text"].strip() != ""
    assert result["filename"] == "sample.txt"


def test_parse_markdown():
    path = os.path.join(FIXTURES, "sample.md")
    result = parse_file(path)
    assert "heading" in result["text"].lower() or len(result["text"]) > 0
    # Should strip markdown formatting
    assert "**" not in result["text"]


def test_parse_html():
    path = os.path.join(FIXTURES, "sample.html")
    result = parse_file(path)
    assert "<" not in result["text"]  # Tags stripped
    assert len(result["text"]) > 0


def test_parse_unsupported():
    with pytest.raises(ValueError, match="Unsupported"):
        parse_file("test.xyz")


def test_parse_returns_pages_for_pdf(tmp_path):
    """PDF parser should return page_numbers metadata."""
    import fitz  # PyMuPDF
    pdf_path = tmp_path / "test.pdf"
    doc = fitz.open()
    page = doc.new_page()
    writer = fitz.TextWriter(page.rect)
    writer.append((72, 72), "Page one content here", fontsize=12)
    writer.write_text(page)
    doc.save(str(pdf_path))
    doc.close()

    result = parse_file(str(pdf_path))
    assert "Page one content" in result["text"]
    assert result.get("pages") is not None


def test_parse_docx(tmp_path):
    """DOCX parser extracts paragraph text."""
    from docx import Document
    doc = Document()
    doc.add_paragraph("Hello from docx")
    doc.add_paragraph("Second paragraph")
    path = tmp_path / "test.docx"
    doc.save(str(path))

    result = parse_file(str(path))
    assert "Hello from docx" in result["text"]
    assert "Second paragraph" in result["text"]
```

**Step 3: Create test fixture files**

`tests/fixtures/sample.txt`:
```
This is a sample text file for testing the parser.
It has multiple lines and some content to extract.
```

`tests/fixtures/sample.md`:
```markdown
# Sample Heading

This is **bold** and *italic* text.

## Another Section

- List item one
- List item two
```

`tests/fixtures/sample.html`:
```html
<html><body>
<h1>Sample Page</h1>
<p>This is a paragraph with <strong>bold</strong> text.</p>
<script>var x = 1;</script>
<style>.hidden { display: none; }</style>
</body></html>
```

**Step 4: Implement parsers.py**

```python
import os
from pathlib import Path

import config


def parse_file(filepath: str) -> dict:
    """Parse a file and return extracted text with metadata.

    Returns:
        dict with keys: text, filename, pages (optional, for PDFs)
    """
    path = Path(filepath)
    ext = path.suffix.lower()

    if ext not in config.SUPPORTED_EXTENSIONS:
        raise ValueError(f"Unsupported file type: {ext}")

    filename = path.name

    if ext == ".txt":
        text = _parse_txt(filepath)
        return {"text": text, "filename": filename}
    elif ext == ".md":
        text = _parse_markdown(filepath)
        return {"text": text, "filename": filename}
    elif ext == ".html":
        text = _parse_html(filepath)
        return {"text": text, "filename": filename}
    elif ext == ".pdf":
        text, pages = _parse_pdf(filepath)
        return {"text": text, "filename": filename, "pages": pages}
    elif ext == ".docx":
        text = _parse_docx(filepath)
        return {"text": text, "filename": filename}

    raise ValueError(f"Unsupported file type: {ext}")


def _parse_txt(filepath: str) -> str:
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def _parse_markdown(filepath: str) -> str:
    import markdown
    from bs4 import BeautifulSoup

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        md_text = f.read()

    html = markdown.markdown(md_text)
    soup = BeautifulSoup(html, "html.parser")
    return soup.get_text(separator="\n")


def _parse_html(filepath: str) -> str:
    from bs4 import BeautifulSoup

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        html = f.read()

    soup = BeautifulSoup(html, "html.parser")

    # Remove script and style elements
    for tag in soup(["script", "style"]):
        tag.decompose()

    return soup.get_text(separator="\n").strip()


def _parse_pdf(filepath: str) -> tuple[str, list[dict]]:
    import fitz  # PyMuPDF

    doc = fitz.open(filepath)
    pages = []
    full_text_parts = []

    for page_num, page in enumerate(doc):
        text = page.get_text()
        pages.append({"page_number": page_num + 1, "text": text})
        full_text_parts.append(text)

    doc.close()
    return "\n\n".join(full_text_parts), pages


def _parse_docx(filepath: str) -> str:
    from docx import Document

    doc = Document(filepath)
    paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
    return "\n\n".join(paragraphs)
```

**Step 5: Run tests**

Run: `python -m pytest tests/test_parsers.py -v`
Expected: All PASS

**Step 6: Commit**

```bash
git add parsers.py tests/test_parsers.py tests/fixtures/
git commit -m "Add file parsers for PDF, DOCX, MD, HTML, TXT

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 4: Embedder (Model Wrapper)

**Files:**
- Create: `embedder.py`

The embedder wraps sentence-transformers. Loading the model takes a few seconds, so it's loaded once and reused.

**Step 1: Implement embedder.py**

```python
import numpy as np
from sentence_transformers import SentenceTransformer

import config

_model: SentenceTransformer | None = None


def load_model() -> SentenceTransformer:
    """Load the embedding model. Called once at startup."""
    global _model
    if _model is None:
        _model = SentenceTransformer(config.EMBEDDING_MODEL)
    return _model


def get_model() -> SentenceTransformer:
    """Get the loaded model. Raises if not loaded yet."""
    if _model is None:
        raise RuntimeError("Embedding model not loaded. Call load_model() first.")
    return _model


def embed_text(text: str) -> list[float]:
    """Embed a single text string. Used for queries."""
    model = get_model()
    vector = model.encode(text, normalize_embeddings=True)
    return vector.tolist()


def embed_batch(texts: list[str]) -> list[list[float]]:
    """Embed a batch of texts. Used for document ingestion."""
    model = get_model()
    vectors = model.encode(texts, normalize_embeddings=True, batch_size=64)
    return vectors.tolist()


def get_embedding_dimension() -> int:
    """Return the dimension of the embedding vectors."""
    model = get_model()
    return model.get_sentence_embedding_dimension()
```

**Step 2: Verify it works**

Run: `python -c "import embedder; embedder.load_model(); v = embedder.embed_text('hello'); print(f'dim={len(v)}, type={type(v[0])}')""`
Expected: `dim=384, type=<class 'float'>` (for MiniLM)

**Step 3: Commit**

```bash
git add embedder.py
git commit -m "Add embedding model wrapper with batch support

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 5: Vector Store (LanceDB Operations)

**Files:**
- Create: `vector_store.py`

LanceDB is embedded — no server needed. Stores data in a directory.

**Step 1: Implement vector_store.py**

```python
import os
from datetime import datetime, timezone

import lancedb
import pyarrow as pa

import config

_db = None
_table = None

TABLE_NAME = "chunks"

SCHEMA = pa.schema([
    pa.field("id", pa.string()),
    pa.field("document_id", pa.string()),
    pa.field("filename", pa.string()),
    pa.field("chunk_index", pa.int32()),
    pa.field("text", pa.string()),
    pa.field("vector", pa.list_(pa.float32(), 384)),
    pa.field("page_number", pa.int32()),
    pa.field("indexed_at", pa.string()),
])


def init_store():
    """Initialize LanceDB connection and ensure table exists."""
    global _db, _table
    os.makedirs(config.LANCEDB_PATH, exist_ok=True)
    _db = lancedb.connect(config.LANCEDB_PATH)

    if TABLE_NAME in _db.table_names():
        _table = _db.open_table(TABLE_NAME)
    else:
        _table = _db.create_table(TABLE_NAME, schema=SCHEMA)


def _get_table():
    if _table is None:
        raise RuntimeError("Vector store not initialized. Call init_store() first.")
    return _table


def insert_chunks(chunks: list[dict]):
    """Insert a list of chunk dicts into the vector store.

    Each dict must have: id, document_id, filename, chunk_index, text, vector,
    page_number, indexed_at
    """
    table = _get_table()
    table.add(chunks)


def search(query_vector: list[float], top_k: int = 5) -> list[dict]:
    """Search for similar vectors. Returns list of result dicts."""
    table = _get_table()

    results = (
        table.search(query_vector)
        .limit(top_k)
        .to_list()
    )

    return [
        {
            "text": r["text"],
            "score": 1.0 - r.get("_distance", 0.0),  # Convert distance to similarity
            "document_id": r["document_id"],
            "filename": r["filename"],
            "chunk_index": r["chunk_index"],
        }
        for r in results
    ]


def delete_document(document_id: str) -> int:
    """Delete all chunks for a document. Returns count of removed chunks."""
    table = _get_table()
    count = table.count_rows(f"document_id = '{document_id}'")
    table.delete(f"document_id = '{document_id}'")
    return count


def list_documents() -> list[dict]:
    """List all unique documents in the store."""
    table = _get_table()

    if table.count_rows() == 0:
        return []

    df = table.to_pandas()
    docs = []
    for doc_id, group in df.groupby("document_id"):
        docs.append({
            "id": doc_id,
            "filename": group["filename"].iloc[0],
            "chunks": len(group),
            "indexed_at": group["indexed_at"].iloc[0],
        })
    return docs


def get_stats() -> dict:
    """Get store statistics."""
    table = _get_table()
    total_chunks = table.count_rows()

    if total_chunks == 0:
        return {"documents": 0, "total_chunks": 0}

    df = table.to_pandas()
    num_docs = df["document_id"].nunique()
    return {"documents": num_docs, "total_chunks": total_chunks}
```

**Step 2: Verify it works**

Run: `python -c "import vector_store; vector_store.init_store(); print(vector_store.get_stats())"`
Expected: `{'documents': 0, 'total_chunks': 0}`

**Step 3: Clean up test data**

Run: `rm -rf ./data/lancedb`

**Step 4: Commit**

```bash
git add vector_store.py
git commit -m "Add LanceDB vector store with insert, search, delete, list

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 6: Document Pipeline (Orchestrator)

**Files:**
- Create: `document_pipeline.py`

Orchestrates: parse → chunk → embed → store. Also handles file saving and ID generation.

**Step 1: Implement document_pipeline.py**

```python
import os
import uuid
import shutil
from datetime import datetime, timezone

import config
from parsers import parse_file
from chunker import chunk_text
from embedder import embed_batch
from vector_store import insert_chunks


def generate_doc_id() -> str:
    """Generate a short unique document ID."""
    return "doc_" + uuid.uuid4().hex[:8]


def ingest_file(filepath: str, original_filename: str) -> dict:
    """Ingest a single file: parse, chunk, embed, store.

    Args:
        filepath: Path to the uploaded temp file
        original_filename: Original name of the uploaded file

    Returns:
        dict with id, filename, chunks count, status
    """
    doc_id = generate_doc_id()
    now = datetime.now(timezone.utc).isoformat()

    # Save original file
    save_dir = os.path.join(config.UPLOAD_PATH, doc_id)
    os.makedirs(save_dir, exist_ok=True)
    saved_path = os.path.join(save_dir, original_filename)
    shutil.copy2(filepath, saved_path)
    file_size = os.path.getsize(saved_path)

    # Parse
    parsed = parse_file(saved_path)
    text = parsed["text"]
    pages = parsed.get("pages")

    # Chunk
    chunks = chunk_text(text, chunk_size=config.CHUNK_SIZE, chunk_overlap=config.CHUNK_OVERLAP)

    if not chunks:
        return {
            "id": doc_id,
            "filename": original_filename,
            "chunks": 0,
            "status": "empty",
            "file_size_bytes": file_size,
        }

    # Embed
    vectors = embed_batch(chunks)

    # Build records for vector store
    records = []
    for i, (chunk, vector) in enumerate(zip(chunks, vectors)):
        page_number = _find_page_number(chunk, pages) if pages else 0
        records.append({
            "id": f"{doc_id}_{i}",
            "document_id": doc_id,
            "filename": original_filename,
            "chunk_index": i,
            "text": chunk,
            "vector": vector,
            "page_number": page_number,
            "indexed_at": now,
        })

    # Store
    insert_chunks(records)

    return {
        "id": doc_id,
        "filename": original_filename,
        "chunks": len(records),
        "status": "indexed",
        "file_size_bytes": file_size,
    }


def _find_page_number(chunk: str, pages: list[dict] | None) -> int:
    """Find which page a chunk most likely came from."""
    if not pages:
        return 0
    for page in pages:
        if chunk[:100] in page["text"]:
            return page["page_number"]
    return 0
```

**Step 2: Commit**

```bash
git add document_pipeline.py
git commit -m "Add document ingestion pipeline: parse, chunk, embed, store

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 7: FastAPI Application (All Routes)

**Files:**
- Create: `app.py`

**Step 1: Implement app.py**

```python
import os
import time
import logging

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

import config
import embedder
import vector_store
from document_pipeline import ingest_file
from models import (
    QueryRequest,
    QueryResponse,
    QueryResult,
    UploadResponse,
    UploadedDocumentInfo,
    DocumentListResponse,
    DocumentInfo,
    DeleteResponse,
    HealthResponse,
)

logging.basicConfig(level=getattr(logging, config.LOG_LEVEL.upper(), logging.INFO))
logger = logging.getLogger(__name__)

app = FastAPI(title="RAG Service", version="1.0.0")

_start_time = time.time()


@app.on_event("startup")
async def startup():
    logger.info("Loading embedding model: %s", config.EMBEDDING_MODEL)
    embedder.load_model()
    logger.info("Embedding model loaded (dim=%d)", embedder.get_embedding_dimension())

    logger.info("Initializing vector store at: %s", config.LANCEDB_PATH)
    vector_store.init_store()
    logger.info("Vector store ready")


@app.get("/")
async def serve_ui():
    return FileResponse("static/index.html")


@app.post("/upload", response_model=UploadResponse)
async def upload_files(files: list[UploadFile] = File(...)):
    results = []
    for file in files:
        ext = os.path.splitext(file.filename or "")[1].lower()
        if ext not in config.SUPPORTED_EXTENSIONS:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported file type: {ext}. Supported: {', '.join(config.SUPPORTED_EXTENSIONS)}",
            )

        # Save uploaded file to temp location
        os.makedirs(config.UPLOAD_PATH, exist_ok=True)
        temp_path = os.path.join(config.UPLOAD_PATH, f"_temp_{file.filename}")
        try:
            content = await file.read()

            if len(content) > config.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
                raise HTTPException(
                    status_code=413,
                    detail=f"File too large. Max size: {config.MAX_UPLOAD_SIZE_MB}MB",
                )

            with open(temp_path, "wb") as f:
                f.write(content)

            result = ingest_file(temp_path, file.filename)
            results.append(
                UploadedDocumentInfo(
                    id=result["id"],
                    filename=result["filename"],
                    chunks=result["chunks"],
                    status=result["status"],
                )
            )
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    return UploadResponse(documents=results)


@app.get("/documents", response_model=DocumentListResponse)
async def list_documents():
    docs = vector_store.list_documents()
    return DocumentListResponse(
        documents=[
            DocumentInfo(
                id=d["id"],
                filename=d["filename"],
                chunks=d["chunks"],
                indexed_at=d["indexed_at"],
                file_size_bytes=_get_file_size(d["id"], d["filename"]),
            )
            for d in docs
        ]
    )


@app.delete("/documents/{doc_id}", response_model=DeleteResponse)
async def delete_document(doc_id: str):
    count = vector_store.delete_document(doc_id)
    if count == 0:
        raise HTTPException(status_code=404, detail=f"Document {doc_id} not found")

    # Remove uploaded file
    upload_dir = os.path.join(config.UPLOAD_PATH, doc_id)
    if os.path.exists(upload_dir):
        import shutil
        shutil.rmtree(upload_dir)

    return DeleteResponse(id=doc_id, deleted=True, chunks_removed=count)


@app.post("/query", response_model=QueryResponse)
async def query(req: QueryRequest):
    start = time.time()

    query_vector = embedder.embed_text(req.query)
    results = vector_store.search(query_vector, top_k=req.top_k)

    elapsed_ms = (time.time() - start) * 1000

    return QueryResponse(
        query=req.query,
        results=[QueryResult(**r) for r in results],
        query_time_ms=round(elapsed_ms, 1),
    )


@app.get("/health", response_model=HealthResponse)
async def health():
    stats = vector_store.get_stats()
    return HealthResponse(
        status="healthy",
        documents=stats["documents"],
        total_chunks=stats["total_chunks"],
        embedding_model=config.EMBEDDING_MODEL,
        uptime_seconds=round(time.time() - _start_time, 1),
    )


def _get_file_size(doc_id: str, filename: str) -> int:
    path = os.path.join(config.UPLOAD_PATH, doc_id, filename)
    if os.path.exists(path):
        return os.path.getsize(path)
    return 0
```

**Step 2: Quick smoke test**

Run: `python -c "from app import app; print(f'Routes: {len(app.routes)}')""`
Expected: `Routes: 7` (5 API + docs + openapi)

**Step 3: Commit**

```bash
git add app.py
git commit -m "Add FastAPI app with all API routes

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 8: Web UI (Drag-and-Drop)

**Files:**
- Create: `static/index.html`

Single self-contained HTML file. Dark theme, no external dependencies.

**Step 1: Create static/index.html**

This is a larger file — a single-page app with:
- Drag-and-drop upload zone
- File picker fallback button
- Upload progress display
- Document list table with delete buttons
- Search test box with results display
- Dark theme, clean utilitarian design
- All CSS and JS inline

The HTML file should:
- Use `fetch()` for API calls
- Poll `/documents` to refresh the list
- Show file type badges
- Display chunk scores on search results
- Show query time

**Step 2: Commit**

```bash
git add static/index.html
git commit -m "Add drag-and-drop web UI for document management and search testing

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 9: Docker Configuration

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `.dockerignore`

**Step 1: Create .dockerignore**

```
__pycache__
*.pyc
.git
data/
*.egg-info
.pytest_cache
tests/
docs/
scripts/
```

**Step 2: Create Dockerfile**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libffi-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Pre-download embedding model at build time
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

COPY . .

EXPOSE 8100
VOLUME /data

ENV EMBEDDING_MODEL=all-MiniLM-L6-v2
ENV LANCEDB_PATH=/data/lancedb
ENV UPLOAD_PATH=/data/uploads
ENV PORT=8100

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8100"]
```

**Step 3: Create docker-compose.yml**

```yaml
services:
  rag:
    build: .
    ports:
      - "8100:8100"
    volumes:
      - rag-data:/data
    environment:
      - EMBEDDING_MODEL=all-MiniLM-L6-v2

volumes:
  rag-data:
```

**Step 4: Commit**

```bash
git add Dockerfile docker-compose.yml .dockerignore
git commit -m "Add Docker configuration

Session: S-2026-02-18-0340-initial-build"
```

---

### Task 10: End-to-End Test

**Step 1: Run the server locally**

Run: `python -m uvicorn app:app --port 8100`
Wait for: "Uvicorn running on http://0.0.0.0:8100"

**Step 2: Test health endpoint**

Run: `curl http://localhost:8100/health | python -m json.tool`
Expected: JSON with status "healthy", 0 documents, 0 chunks

**Step 3: Test upload**

Run: `curl -X POST http://localhost:8100/upload -F "files=@tests/fixtures/sample.txt"`
Expected: JSON with document id, filename, chunk count, status "indexed"

**Step 4: Test document list**

Run: `curl http://localhost:8100/documents | python -m json.tool`
Expected: JSON listing the uploaded document

**Step 5: Test query**

Run: `curl -X POST http://localhost:8100/query -H "Content-Type: application/json" -d '{"query": "sample text", "top_k": 3}'`
Expected: JSON with results array, query_time_ms

**Step 6: Test delete**

Run: `curl -X DELETE http://localhost:8100/documents/{DOC_ID}`
Expected: JSON with deleted: true

**Step 7: Test web UI**

Open `http://localhost:8100` in browser.
Verify: drag-and-drop zone, document list, search box all functional.

**Step 8: Docker build and test**

Run: `docker build -t rag-service . && docker run -d -p 8100:8100 -v rag-data:/data --name rag-test rag-service`
Repeat health/upload/query tests against Docker container.

Run: `docker stop rag-test && docker rm rag-test`

**Step 9: Final commit — update session doc**

Update `docs/project-memory/sessions/S-2026-02-18-0340-initial-build.md` with all changes made and commits.

```bash
git add docs/project-memory/sessions/S-2026-02-18-0340-initial-build.md
git commit -m "Complete initial RAG service build — all components working

Session: S-2026-02-18-0340-initial-build"
```
