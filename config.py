import os

PORT = int(os.getenv("PORT", "8100"))
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "nomic-ai/nomic-embed-text-v1.5")
LANCEDB_PATH = os.getenv("LANCEDB_PATH", "./data/lancedb")

# Models that require task-specific prefixes for queries vs documents.
# Keys are substrings matched against the model name.
TASK_PREFIX_MODELS: dict[str, tuple[str, str]] = {
    "nomic-embed-text": ("search_query: ", "search_document: "),
}
UPLOAD_PATH = os.getenv("UPLOAD_PATH", "./data/uploads")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "500"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "50"))
MAX_UPLOAD_SIZE_MB = int(os.getenv("MAX_UPLOAD_SIZE_MB", "50"))
TOP_K_DEFAULT = int(os.getenv("TOP_K_DEFAULT", "5"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

SUPPORTED_EXTENSIONS = {".pdf", ".md", ".txt", ".docx", ".html"}
