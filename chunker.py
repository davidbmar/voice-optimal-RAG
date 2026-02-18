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
