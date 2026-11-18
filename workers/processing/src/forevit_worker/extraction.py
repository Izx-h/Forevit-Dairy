"""Bounded document extraction and source-aware deterministic chunking."""
from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass
from typing import Iterable

MAX_ARCHIVE_MEMBERS = 10_000
MAX_ARCHIVE_UNCOMPRESSED = 100 * 1024 * 1024
MAX_TEXT_CHARS = 2_000_000


class ExtractionError(Exception):
    """A safe, user-displayable extraction failure with a stable code."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class TextUnit:
    text: str
    page_no: int | None = None
    section_label: str | None = None


@dataclass(frozen=True)
class Chunk:
    chunk_no: int
    page_no: int | None
    section_label: str | None
    content: str
    metadata: dict


def _safe_zip(data: bytes) -> zipfile.ZipFile:
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
        entries = archive.infolist()
        if len(entries) > MAX_ARCHIVE_MEMBERS or sum(e.file_size for e in entries) > MAX_ARCHIVE_UNCOMPRESSED:
            archive.close()
            raise ExtractionError("document_too_large")
        if any(e.flag_bits & 0x1 for e in entries):
            archive.close()
            raise ExtractionError("encrypted_document_unsupported")
        return archive
    except zipfile.BadZipFile as exc:
        raise ExtractionError("invalid_document") from exc


def _ocr_pdf(data: bytes) -> list[TextUnit]:
    try:
        from pdf2image import convert_from_bytes
        import pytesseract
        images = convert_from_bytes(data, dpi=120, first_page=1, last_page=100)
        units = []
        for page_no, image in enumerate(images, start=1):
            text = pytesseract.image_to_string(image).strip()
            if text:
                units.append(TextUnit(text, page_no, None))
        if units:
            return units
        raise ExtractionError("invalid_document")
    except ExtractionError:
        raise
    except ImportError as exc:
        raise ExtractionError("extractor_unavailable") from exc
    except Exception as exc:
        raise ExtractionError("extractor_unavailable") from exc


def extract_document(data: bytes, file_name: str, mime_type: str) -> list[TextUnit]:
    """Extract supported formats without executing document content or macros."""
    suffix = file_name.rsplit(".", 1)[-1].lower() if "." in file_name else ""
    try:
        if suffix == "txt" or mime_type.startswith("text/plain"):
            text = data.decode("utf-8-sig", errors="replace")
            units = [TextUnit(t.strip(), page_no, None)
                     for page_no, t in enumerate(re.split(r"\f", text), start=1) if t.strip()]
            if not units and text.strip():
                units = [TextUnit(text.strip())]
        elif suffix == "pdf" or mime_type == "application/pdf":
            from pypdf import PdfReader
            reader = PdfReader(io.BytesIO(data), strict=True)
            if reader.is_encrypted:
                raise ExtractionError("encrypted_document_unsupported")
            units = []
            for page_no, page in enumerate(reader.pages, start=1):
                text = (page.extract_text() or "").strip()
                if text:
                    units.append(TextUnit(text, page_no, None))
            if not units:
                units = _ocr_pdf(data)
        elif suffix == "docx":
            from docx import Document
            with _safe_zip(data):
                doc = Document(io.BytesIO(data))
                units, section = [], None
                for paragraph in doc.paragraphs:
                    text = paragraph.text.strip()
                    if not text:
                        continue
                    style = getattr(paragraph.style, "name", "") or ""
                    if style.lower().startswith("heading"):
                        section = text[:200]
                    units.append(TextUnit(text, None, section))
                for table_no, table in enumerate(doc.tables, start=1):
                    rows = []
                    for row in table.rows:
                        cells = [re.sub(r"\s+", " ", c.text).strip() for c in row.cells]
                        if any(cells):
                            rows.append(" | ".join(cells))
                    if rows:
                        units.append(TextUnit("Table: " + "\n".join(rows), None, f"Table {table_no}"))
        elif suffix == "xlsx":
            from openpyxl import load_workbook
            with _safe_zip(data):
                book = load_workbook(io.BytesIO(data), read_only=True, data_only=True, keep_links=False)
                units = []
                try:
                    for sheet in book.worksheets:
                        rows = []
                        for row in sheet.iter_rows(values_only=True):
                            values = [str(v).strip() if v is not None else "" for v in row]
                            if any(values):
                                rows.append(" | ".join(values))
                        if rows:
                            units.append(TextUnit("\n".join(rows), None, sheet.title[:200]))
                finally:
                    book.close()
        elif suffix == "pptx":
            from pptx import Presentation
            with _safe_zip(data):
                presentation = Presentation(io.BytesIO(data))
                units = []
                for page_no, slide in enumerate(presentation.slides, start=1):
                    texts = [shape.text.strip() for shape in slide.shapes if getattr(shape, "has_text_frame", False) and shape.text.strip()]
                    if texts:
                        units.append(TextUnit("\n".join(texts), page_no, texts[0][:200]))
        else:
            raise ExtractionError("unsupported_file_type")
    except ExtractionError:
        raise
    except ImportError as exc:
        raise ExtractionError("extractor_unavailable") from exc
    except Exception as exc:
        # Do not surface parser messages; they can include file contents or paths.
        raise ExtractionError("invalid_document") from exc

    units = [u for u in units if u.text.strip()]
    total = sum(len(u.text) for u in units)
    if total > MAX_TEXT_CHARS:
        raise ExtractionError("document_too_large")
    return units


def split_units(units: Iterable[TextUnit], chunk_chars: int = 1400, overlap_chars: int = 180) -> list[Chunk]:
    """Split text into bounded overlapping chunks, retaining page/section metadata."""
    if chunk_chars < 1 or overlap_chars < 0 or overlap_chars >= chunk_chars:
        raise ValueError("invalid chunk size or overlap")
    chunks: list[Chunk] = []
    for unit in units:
        text = re.sub(r"\s+", " ", unit.text).strip()
        start = 0
        while start < len(text):
            end = min(start + chunk_chars, len(text))
            # Prefer a natural word boundary when it does not make a tiny chunk.
            if end < len(text):
                boundary = text.rfind(" ", start + chunk_chars // 2, end)
                if boundary > start:
                    end = boundary
            piece = text[start:end].strip()
            if piece:
                chunks.append(Chunk(len(chunks), unit.page_no, unit.section_label, piece,
                                    {"source_page": unit.page_no, "source_section": unit.section_label}))
            if end >= len(text):
                break
            start = max(start + 1, end - overlap_chars)
    return chunks
