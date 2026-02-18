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
        dict with id, filename, chunks count, status, file_size_bytes
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
