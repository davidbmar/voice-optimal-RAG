import logging
import os
from datetime import datetime, timezone

import lancedb
import pyarrow as pa

import config
import embedder

logger = logging.getLogger(__name__)

_db = None
_table = None

TABLE_NAME = "chunks"


def _build_schema(dim: int) -> pa.Schema:
    """Build the table schema with the given vector dimension."""
    return pa.schema([
        pa.field("id", pa.string()),
        pa.field("document_id", pa.string()),
        pa.field("filename", pa.string()),
        pa.field("chunk_index", pa.int32()),
        pa.field("text", pa.string()),
        pa.field("vector", pa.list_(pa.float32(), dim)),
        pa.field("page_number", pa.int32()),
        pa.field("indexed_at", pa.string()),
    ])


def init_store():
    """Initialize LanceDB connection and ensure table exists.

    Detects vector dimension mismatches (e.g. model upgrade from 384-dim to
    768-dim) and recreates the table automatically. The nightly cron will
    re-index all documents.
    """
    global _db, _table
    os.makedirs(config.LANCEDB_PATH, exist_ok=True)
    _db = lancedb.connect(config.LANCEDB_PATH)

    dim = embedder.get_embedding_dimension()
    schema = _build_schema(dim)

    if TABLE_NAME in _db.table_names():
        existing = _db.open_table(TABLE_NAME)
        existing_schema = existing.to_arrow().schema
        vec_field = existing_schema.field("vector")
        existing_dim = vec_field.type.list_size
        if existing_dim != dim:
            logger.warning(
                "Vector dimension mismatch: table has %d, model produces %d. "
                "Dropping table for re-creation.",
                existing_dim,
                dim,
            )
            _db.drop_table(TABLE_NAME)
            _table = _db.create_table(TABLE_NAME, schema=schema)
        else:
            _table = existing
    else:
        _table = _db.create_table(TABLE_NAME, schema=schema)


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
            "score": round(1.0 / (1.0 + r.get("_distance", 0.0)), 4),
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
    if count > 0:
        table.delete(f"document_id = '{document_id}'")
    return count


def list_documents() -> list[dict]:
    """List all unique documents in the store."""
    table = _get_table()

    if table.count_rows() == 0:
        return []

    # Use PyArrow directly instead of pandas
    arrow_table = table.to_arrow()
    doc_ids = arrow_table.column("document_id").to_pylist()
    filenames = arrow_table.column("filename").to_pylist()
    indexed_ats = arrow_table.column("indexed_at").to_pylist()

    # Group by document_id
    doc_map: dict[str, dict] = {}
    for doc_id, filename, indexed_at in zip(doc_ids, filenames, indexed_ats):
        if doc_id not in doc_map:
            doc_map[doc_id] = {
                "id": doc_id,
                "filename": filename,
                "chunks": 0,
                "indexed_at": indexed_at,
            }
        doc_map[doc_id]["chunks"] += 1

    return list(doc_map.values())


def get_stats() -> dict:
    """Get store statistics."""
    table = _get_table()
    total_chunks = table.count_rows()

    if total_chunks == 0:
        return {"documents": 0, "total_chunks": 0}

    # Use PyArrow directly instead of pandas
    arrow_table = table.to_arrow()
    unique_docs = len(set(arrow_table.column("document_id").to_pylist()))
    return {"documents": unique_docs, "total_chunks": total_chunks}
