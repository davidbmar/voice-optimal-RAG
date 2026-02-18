from pydantic import BaseModel, Field


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
