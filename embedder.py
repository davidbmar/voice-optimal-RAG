from sentence_transformers import SentenceTransformer

import config

_model: SentenceTransformer | None = None


def _get_task_prefixes() -> tuple[str, str]:
    """Return (query_prefix, doc_prefix) for the current model.

    Checks config.TASK_PREFIX_MODELS for substring matches against the model
    name. Returns empty strings for models that don't use task prefixes.
    """
    model_name = config.EMBEDDING_MODEL.lower()
    for substring, prefixes in config.TASK_PREFIX_MODELS.items():
        if substring.lower() in model_name:
            return prefixes
    return ("", "")


def load_model() -> SentenceTransformer:
    """Load the embedding model. Called once at startup."""
    global _model
    if _model is None:
        _model = SentenceTransformer(
            config.EMBEDDING_MODEL, trust_remote_code=True
        )
    return _model


def get_model() -> SentenceTransformer:
    """Get the loaded model. Raises if not loaded yet."""
    if _model is None:
        raise RuntimeError("Embedding model not loaded. Call load_model() first.")
    return _model


def embed_text(text: str) -> list[float]:
    """Embed a single text string. Used for queries."""
    model = get_model()
    query_prefix, _ = _get_task_prefixes()
    vector = model.encode(query_prefix + text, normalize_embeddings=True)
    return vector.tolist()


def embed_batch(texts: list[str]) -> list[list[float]]:
    """Embed a batch of texts. Used for document ingestion."""
    model = get_model()
    _, doc_prefix = _get_task_prefixes()
    prefixed = [doc_prefix + t for t in texts]
    vectors = model.encode(prefixed, normalize_embeddings=True, batch_size=64)
    return vectors.tolist()


def get_embedding_dimension() -> int:
    """Return the dimension of the embedding vectors."""
    model = get_model()
    return model.get_sentence_embedding_dimension()
