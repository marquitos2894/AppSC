from __future__ import annotations

import os
from tempfile import SpooledTemporaryFile

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from .extractor import extract_purchase_request


app = FastAPI(title="AppSC PDF Extractor")


def allowed_origins() -> list[str]:
    locales = ["http://127.0.0.1:5173", "http://localhost:5173"]
    produccion = [
        origen.strip().rstrip("/")
        for origen in os.getenv("ALLOWED_ORIGINS", "").split(",")
        if origen.strip()
    ]
    return list(dict.fromkeys([*locales, *produccion]))

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins(),
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/extract")
async def extract(file: UploadFile = File(...)) -> dict:
    content_type = (file.content_type or "").lower()
    filename = (file.filename or "").lower()
    if "pdf" not in content_type and not filename.endswith(".pdf"):
        raise HTTPException(status_code=400, detail="El archivo debe ser PDF")

    spool = SpooledTemporaryFile(max_size=12 * 1024 * 1024, mode="w+b")
    try:
        while chunk := await file.read(1024 * 1024):
            spool.write(chunk)
        spool.seek(0)
        return extract_purchase_request(spool)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"No se pudo extraer el PDF: {exc}") from exc
    finally:
        spool.close()
