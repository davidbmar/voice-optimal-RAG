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
