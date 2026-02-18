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
    text = " ".join(f"sentence{i} word word word word." for i in range(200))
    chunks = chunk_text(text, chunk_size=100, chunk_overlap=20)
    assert len(chunks) >= 2
    # Check that the end of chunk 0 appears at the start of chunk 1
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
