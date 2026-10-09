"""
natlas-mobile · serve/app.py
=============================
Docker Compose entrypoint. Loads the models at import time and exposes the
FastAPI app as `api`, so uvicorn can serve it:

    uvicorn app:api --host 0.0.0.0 --port 8000

Request handling lives in gateway.py, shared with the Modal deployment
(modal_app.py), so the two cannot drift apart.

Environment:
    HF_TOKEN          — Hugging Face token with access to all 5 gated repos
    NATLAS_API_KEY    — bearer key clients must present
    MODEL_CACHE_DIR   — where to cache weights (default /model-cache)

Needs an NVIDIA GPU with ~24 GB of VRAM. For a cloud deployment that scales to
zero instead, use modal_app.py.
"""

from __future__ import annotations

import os

import gateway

CACHE_DIR = os.environ.get("MODEL_CACHE_DIR", "/model-cache")


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"{name} is not set. Copy .env.example to serve/.env and fill it in."
        )
    return value


# Loading happens at import time: uvicorn then only serves requests once every
# model is on the GPU, so /health never answers "ok" prematurely.
_service = gateway.load_models(
    cache_dir=CACHE_DIR,
    hf_token=_require("HF_TOKEN"),
    api_key=_require("NATLAS_API_KEY"),
)

api = gateway.build_api(_service)
