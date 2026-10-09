"""
natlas-mobile · serve/modal_app.py
===================================
Deploys N-ATLaS (LLM) + four ASR models behind a single OpenAI-compatible
gateway on Modal. One A10G covers everything.

The request handling lives in gateway.py, shared with the Docker Compose
deployment (app.py), so the two cannot drift apart.

Deploy:
    modal deploy serve/modal_app.py

Secrets (one Modal secret, named by MODAL_SECRET_NAME — default "natlas-api"):
    HF_TOKEN          — Hugging Face token with access to all 5 gated repos
    NATLAS_API_KEY    — bearer key clients must present

Endpoints (under the deployed app URL):
    GET  /health
    POST /v1/chat/completions
    POST /v1/audio/transcriptions
"""

from __future__ import annotations

import os

import modal

# ── Image ─────────────────────────────────────────────────────────────────────

BASE_IMAGE = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg")
    .pip_install(
        "fastapi>=0.111",
        "uvicorn[standard]>=0.29",
        "python-multipart>=0.0.9",
        "pydantic>=2.7",
        "huggingface_hub>=0.23",
        "transformers>=4.41",
        "torch>=2.3",
        "torchaudio>=2.3",
        "accelerate>=0.30",
        "vllm>=0.4.3",
        "soundfile>=0.12",   # reads the WAV chunks into numpy for the ASR pipe
        "numpy>=1.26",
    )
    .env(
        {
            # vLLM 0.31 defaults to FlashInfer for top-p/top-k sampling, which
            # JIT-compiles its kernels and so needs nvcc. debian_slim has no
            # CUDA toolkit, so engine startup dies with:
            #   RuntimeError: Could not find nvcc and default
            #   cuda_home='/usr/local/cuda' doesn't exist
            # The PyTorch-native sampler needs no compiler.
            "VLLM_USE_FLASHINFER_SAMPLER": "0",
        }
    )
    # Ship the shared gateway module into the image.
    .add_local_python_source("gateway")
)

# ── Modal app ─────────────────────────────────────────────────────────────────

app = modal.App("natlas-serve")

# Persistent volume caches the ~16 GB of weights between cold starts.
model_cache = modal.Volume.from_name("natlas-model-cache", create_if_missing=True)

SECRET = modal.Secret.from_name(os.environ.get("MODAL_SECRET_NAME", "natlas-api"))

CACHE_DIR = "/model-cache"


@app.cls(
    gpu="A10G",
    image=BASE_IMAGE,
    secrets=[SECRET],
    volumes={CACHE_DIR: model_cache},
    timeout=600,
    # Keep the container (and its loaded models) alive for 5 minutes after the
    # last request. A cold start reloads five models onto the GPU, so this
    # matters. 20 minutes is Modal's maximum. For a live demo, add
    # min_containers=1 to hold a container permanently.
    scaledown_window=300,
)
class NAtlasService:
    """Runs the LLM (vLLM) and all four ASR models on a single A10G."""

    @modal.enter()
    def load(self):
        import gateway

        self._service = gateway.load_models(
            cache_dir=CACHE_DIR,
            hf_token=os.environ["HF_TOKEN"],
            api_key=os.environ["NATLAS_API_KEY"],
        )

    @modal.asgi_app()
    def serve(self):
        import gateway

        return gateway.build_api(self._service)
