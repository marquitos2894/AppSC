from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from tempfile import SpooledTemporaryFile
from typing import BinaryIO, Iterable

import pdfplumber


END_TABLE_RE = re.compile(r"comentarios del autorizador", re.IGNORECASE)
SC_RE = re.compile(r"N\S?\s*S\.?\s*C\.?\s*[:.\-\s]*(\d+)", re.IGNORECASE)
DATE_RE = re.compile(r"Fecha de documento:\s*(\d{1,2}-\d{1,2}-\d{4})", re.IGNORECASE)
REQUEST_DATE_RE = re.compile(r"FECHA DE SOLICITUD:\s*(\d{1,2}-\d{1,2}-\d{4})", re.IGNORECASE)
COST_GROUP_RE = re.compile(r"Grupo de Costo:\s*(.+)", re.IGNORECASE)
MOTIVO_RE = re.compile(r"\bMotivo\s*\n\s*(.+)", re.IGNORECASE)


def extract_purchase_request(file: str | Path | BinaryIO) -> dict:
    with pdfplumber.open(file) as pdf:
        text = "\n".join(page.extract_text() or "" for page in pdf.pages)
        table_rows = []
        for page in pdf.pages:
            for table in page.extract_tables():
                table_rows.extend(table)

    return {
        "nro_sc": extract_sc(text),
        "fecha_emision": extract_date(text),
        "motivo": clean_text(match_one(MOTIVO_RE, text)),
        "grupo_costo": extract_cost_group(text),
        "items": extract_items(table_rows),
        "text": text,
    }


def extract_sc(text: str) -> str | None:
    value = match_one(SC_RE, text)
    if value:
        return value
    fallback = re.search(r"\bSC\s*0*(\d{3,8})\b", text, re.IGNORECASE)
    return fallback.group(1) if fallback else None


def extract_date(text: str) -> str | None:
    return match_one(DATE_RE, text) or match_one(REQUEST_DATE_RE, text)


def extract_cost_group(text: str) -> str | None:
    value = match_one(COST_GROUP_RE, text)
    if not value:
        return None
    return clean_text(value.split("Centro de Costos:")[0])


def extract_items(rows: Iterable[list[str | None]]) -> list[dict]:
    items = []
    header_indexes: dict[str, int] | None = None

    for row in rows:
        cells = [clean_text(cell) for cell in row]
        joined = " ".join(cell for cell in cells if cell)
        if END_TABLE_RE.search(joined):
            break

        maybe_header = detect_header(cells)
        if maybe_header:
            header_indexes = maybe_header
            continue

        if not header_indexes or not is_item_row(cells, header_indexes):
            continue

        item = row_to_item(cells, header_indexes)
        if item:
            items.append(item)

    return items


def detect_header(cells: list[str]) -> dict[str, int] | None:
    normalized = [normalize_header(cell) for cell in cells]
    has_purchase_table = any("material componente" in cell for cell in normalized)
    if not has_purchase_table:
        return None

    if len(cells) >= 10:
        return {
            "codigo": 1,
            "nro_parte": 2,
            "material": 3,
            "cantidad_solicitada": 4,
            "cantidad_aprobada": 5,
            "equipo": 9,
            "sistema": 8,
        }

    def find(*names: str) -> int | None:
        for name in names:
            if name in normalized:
                return normalized.index(name)
        return None

    return {
        "codigo": find("codigo erp"),
        "nro_parte": find("nro parte"),
        "material": find("nombre material componente"),
        "cantidad_solicitada": find("cantidad solicitada"),
        "cantidad_aprobada": find("cantidad aprobada"),
        "equipo": find("equipo"),
        "sistema": find("sistema de equipo"),
    }


def is_item_row(cells: list[str], header: dict[str, int]) -> bool:
    codigo_idx = header.get("codigo")
    material_idx = header.get("material")
    qty_idx = header.get("cantidad_aprobada") or header.get("cantidad_solicitada")
    if codigo_idx is None or material_idx is None or qty_idx is None:
        return False
    return bool(cells[codigo_idx] and cells[material_idx] and parse_number(cells[qty_idx]) is not None)


def row_to_item(cells: list[str], header: dict[str, int]) -> dict | None:
    material = get_cell(cells, header.get("material"))
    qty = parse_number(get_cell(cells, header.get("cantidad_aprobada"))) or parse_number(
        get_cell(cells, header.get("cantidad_solicitada"))
    )
    if not material or qty is None:
        return None

    return {
        "nro_parte": get_cell(cells, header.get("nro_parte")).replace(" ", ""),
        "material": material,
        "equipo": normalize_equipment(get_cell(cells, header.get("equipo"))),
        "cantidad_solicitada": qty,
    }


def normalize_equipment(value: str) -> str:
    first_line = value.splitlines()[0] if value else ""
    value = re.sub(r"\s+", " ", first_line).strip()
    match = re.search(r"([A-Z]{1,6})\s*-?\s*(\d{1,4})", value, re.IGNORECASE)
    if not match:
        return value
    return f"{match.group(1).upper()}-{match.group(2)}"


def normalize_header(value: str) -> str:
    value = value.lower().replace("/", " ")
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def clean_text(value: str | None) -> str:
    if not value:
        return ""
    value = value.replace("\ufffd", "°")
    return re.sub(r"\s+", " ", value).strip()


def get_cell(cells: list[str], index: int | None) -> str:
    if index is None or index >= len(cells):
        return ""
    return cells[index] or ""


def parse_number(value: str) -> float | None:
    match = re.search(r"\d+(?:[.,]\d+)?", value or "")
    if not match:
        return None
    return float(match.group(0).replace(",", "."))


def match_one(regex: re.Pattern, text: str) -> str | None:
    match = regex.search(text)
    return match.group(1).strip() if match else None


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Uso: python -m app.extractor archivo.pdf")
    print(json.dumps(extract_purchase_request(sys.argv[1]), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
