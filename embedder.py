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
