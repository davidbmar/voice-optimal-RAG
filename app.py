import os
import time
import logging

from fastapi import FastAPI, UploadFile, File, HTTPException
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
        safe_temp_name = file.filename.replace("/", "__").replace("\\", "__")
        temp_path = os.path.join(config.UPLOAD_PATH, f"_temp_{safe_temp_name}")
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
