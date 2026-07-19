"""
OMR FastAPI Server — exposes the OMR pipeline as a REST API.

Endpoints:
  POST /api/omr/scan       — scan a single image, returns OmrResult JSON
  POST /api/omr/scan-batch — scan multiple images, returns list of OmrResult JSONs
  GET  /api/omr/health     — health check

Start:
  uvicorn server:app --host 0.0.0.0 --port 8000
  python server.py          (auto-starts on port 8000)
"""

import json, os, tempfile, uuid
from typing import Optional

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
import cv2

from omr_processor import (
    process_omr, load_image, preprocess, detect_page, four_point_transform,
    read_answer_bubbles, read_id_bubbles, grade, OmrResult
)

app = FastAPI(title="ATLAS OMR Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory layout cache (keyed by layout_hash sent from client)
_layout_cache: dict = {}


@app.get("/api/omr/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


@app.post("/api/omr/scan")
async def scan_omr(
    image: UploadFile = File(...),
    layout_json: str = Form(...),
    answer_key_json: str = Form(default="{}"),
    marker: Optional[UploadFile] = File(default=None),
):
    """
    Scan a single OMR bubble sheet image.

    - image: the captured photo (PNG/JPEG)
    - layout_json: JSON string of the layout metadata
    - answer_key_json: JSON string of {"1":"A","2":"B",...} (optional)
    - marker: corner marker image (optional)
    """
    try:
        layout = json.loads(layout_json)
        answer_key = json.loads(answer_key_json)
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

    # Save uploaded image to temp file
    suffix = os.path.splitext(image.filename or "scan.jpg")[1] or ".jpg"
    tmp_path = os.path.join(tempfile.gettempdir(), f"omr_{uuid.uuid4().hex}{suffix}")
    try:
        contents = await image.read()
        with open(tmp_path, "wb") as f:
            f.write(contents)

        # Save marker if provided
        marker_path = None
        if marker:
            marker_contents = await marker.read()
            marker_path = os.path.join(tempfile.gettempdir(), f"marker_{uuid.uuid4().hex}.png")
            with open(marker_path, "wb") as f:
                f.write(marker_contents)

        result = process_omr(tmp_path, layout, answer_key, marker_path)
        return JSONResponse(content=result.to_dict())

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        if marker_path and os.path.exists(marker_path):
            os.remove(marker_path)


@app.post("/api/omr/scan-batch")
async def scan_batch(
    images: list[UploadFile] = File(...),
    layout_json: str = Form(...),
    answer_key_json: str = Form(default="{}"),
):
    """
    Scan multiple OMR bubble sheet images in one request.
    Returns a list of OmrResult JSONs.
    """
    try:
        layout = json.loads(layout_json)
        answer_key = json.loads(answer_key_json)
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")

    results = []
    for img in images:
        suffix = os.path.splitext(img.filename or "scan.jpg")[1] or ".jpg"
        tmp_path = os.path.join(tempfile.gettempdir(), f"omr_{uuid.uuid4().hex}{suffix}")
        try:
            contents = await img.read()
            with open(tmp_path, "wb") as f:
                f.write(contents)
            result = process_omr(tmp_path, layout, answer_key)
            results.append(result.to_dict())
        except Exception as e:
            results.append({"error": str(e), "file": img.filename})
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)

    return JSONResponse(content={"results": results})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)
