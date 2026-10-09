"""
natlas-mobile · serve/gateway.py
=================================
Shared gateway logic for both deployment targets.

`modal_app.py` (Modal) and `app.py` (Docker Compose) both build their FastAPI
app from `build_api()` here, so the two deployments cannot drift apart.

Audio helpers live here too, since the ffmpeg conversion and 28-second chunking
are identical either way.
"""

# NOTE: deliberately no `from __future__ import annotations` here.
# It stringifies annotations, and FastAPI resolves them with get_type_hints(),
# which only sees MODULE globals. The FastAPI types (Request, UploadFile, File,
# Form) are imported inside build_api(), so they would be unresolvable and
# FastAPI would silently treat `request: Request` as a query parameter --
# every POST then fails with:
#   422 {"loc":["query","request"],"msg":"Field required"}
# Python 3.10+ evaluates `str | None` natively, so nothing here needs it.

import hashlib
import hmac
import io
import json
import os
import subprocess
import tempfile
import time
from collections.abc import AsyncIterator
from datetime import date

# Language code → Hugging Face ASR repo
ASR_REPOS: dict[str, str] = {
    "ha": "NCAIR1/Hausa-ASR",
    "ig": "NCAIR1/Igbo-ASR",
    "yo": "NCAIR1/Yoruba-ASR",
    "en": "NCAIR1/NigerianAccentedEnglish",
}

LLM_REPO = "NCAIR1/N-ATLaS"

LANGUAGE_NAMES = {
    "ha": "Hausa",
    "ig": "Igbo",
    "yo": "Yorùbá",
    "en": "Nigerian English",
}

# N-ATLaS context window
MAX_MODEL_LEN = 8092

# Whisper takes a 30 s window; leave headroom so no chunk is rejected.
CHUNK_SECONDS = 28


# ── Auth ──────────────────────────────────────────────────────────────────────

def check_bearer(authorization: str | None, api_key: str) -> None:
    """Validate the bearer token without leaking its length or content via timing."""
    from fastapi import HTTPException

    def reject():
        raise HTTPException(status_code=401, detail="Invalid or missing API key")

    if not authorization or not authorization.startswith("Bearer "):
        reject()

    token = authorization.split(" ", 1)[1]
    # Hash both sides first so compare_digest sees equal-length inputs
    # regardless of the supplied token's length.
    expected = hashlib.sha256(api_key.encode()).digest()
    supplied = hashlib.sha256(token.encode()).digest()
    if not hmac.compare_digest(expected, supplied):
        reject()


# ── Audio ─────────────────────────────────────────────────────────────────────

def to_16k_mono_wav(audio_bytes: bytes, src_format: str = "ogg") -> bytes:
    """Convert arbitrary audio to 16 kHz mono WAV using ffmpeg."""
    with tempfile.TemporaryDirectory() as tmp:
        src_path = os.path.join(tmp, f"input.{src_format}")
        out_path = os.path.join(tmp, "output.wav")

        with open(src_path, "wb") as f:
            f.write(audio_bytes)

        subprocess.run(
            [
                "ffmpeg", "-y", "-i", src_path,
                "-ar", "16000", "-ac", "1", "-f", "wav", out_path,
            ],
            check=True,
            capture_output=True,
        )

        with open(out_path, "rb") as f:
            return f.read()


def chunk_audio(wav_bytes: bytes, chunk_seconds: int = CHUNK_SECONDS) -> list[bytes]:
    """Split a WAV into chunks of at most `chunk_seconds`."""
    import wave

    chunks: list[bytes] = []

    with io.BytesIO(wav_bytes) as buf, wave.open(buf) as wf:
        framerate = wf.getframerate()
        frames_per_chunk = framerate * chunk_seconds

        while True:
            frames = wf.readframes(frames_per_chunk)
            if not frames:
                break
            chunk_buf = io.BytesIO()
            with wave.open(chunk_buf, "wb") as cw:
                cw.setnchannels(wf.getnchannels())
                cw.setsampwidth(wf.getsampwidth())
                cw.setframerate(framerate)
                cw.writeframes(frames)
            chunks.append(chunk_buf.getvalue())

    return chunks or [wav_bytes]


# ── Prompt assembly ───────────────────────────────────────────────────────────

def build_prompt(tokenizer, messages: list[dict], language: str) -> str:
    """Apply the Llama-3 chat template, injecting a language hint if needed."""
    if not any(m.get("role") == "system" for m in messages):
        name = LANGUAGE_NAMES.get(language, "English")
        messages = [
            {
                "role": "system",
                "content": (
                    f"You are a helpful assistant. "
                    f"The user is communicating in {name}. "
                    f"Respond in {name} unless asked otherwise."
                ),
            }
        ] + messages

    # The Llama-3 template requires date_string.
    return tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
        date_string=date.today().strftime("%d %b %Y"),
    )


# ── FastAPI app ───────────────────────────────────────────────────────────────

def build_api(service):
    """
    Build the FastAPI app.

    `service` supplies the loaded models and must expose:
        service.llm        — vLLM AsyncLLMEngine
        service.tokenizer  — the LLM's tokenizer
        service.asr        — dict[lang_code, transformers ASR pipeline]
        service.api_key    — the expected bearer token
    """
    from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse, StreamingResponse
    from vllm import SamplingParams
    from vllm.utils import random_uuid

    api = FastAPI(title="natlas-mobile gateway", version="0.1.0")
    api.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type"],
    )

    # ── /health ───────────────────────────────────────────────────────────────
    @api.get("/health")
    async def health():
        return {
            "status": "ok",
            "models": {
                "llm": LLM_REPO,
                "asr": list(ASR_REPOS.values()),
            },
            "timestamp": int(time.time()),
        }

    # ── /v1/chat/completions ──────────────────────────────────────────────────
    @api.post("/v1/chat/completions")
    async def chat_completions(request: Request):
        check_bearer(request.headers.get("Authorization"), service.api_key)
        body = await request.json()

        messages = body.get("messages", [])
        if not messages:
            raise HTTPException(status_code=400, detail="messages must not be empty")

        language = body.get("language", "en")
        if language not in LANGUAGE_NAMES:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported language '{language}'. Use: {list(LANGUAGE_NAMES)}",
            )

        temperature = float(body.get("temperature", 0.7))
        max_tokens = int(body.get("max_tokens", 512))
        stream = bool(body.get("stream", False))

        prompt = build_prompt(service.tokenizer, messages, language)

        sampling = SamplingParams(
            temperature=temperature,
            max_tokens=max_tokens,
            repetition_penalty=1.12,
        )
        request_id = random_uuid()

        if not stream:
            output = None
            async for out in service.llm.generate(prompt, sampling, request_id):
                output = out
            content = output.outputs[0].text if output else ""
            return JSONResponse({
                "id": f"chatcmpl-{request_id}",
                "object": "chat.completion",
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": content},
                    }
                ],
                "usage": {
                    "prompt_tokens": len(output.prompt_token_ids) if output else 0,
                    "completion_tokens": (
                        len(output.outputs[0].token_ids) if output else 0
                    ),
                },
            })

        async def event_stream() -> AsyncIterator[str]:
            prev_len = 0
            async for out in service.llm.generate(prompt, sampling, request_id):
                text = out.outputs[0].text
                delta = text[prev_len:]
                prev_len = len(text)
                if delta:
                    chunk = {
                        "id": f"chatcmpl-{request_id}",
                        "object": "chat.completion.chunk",
                        "choices": [{"index": 0, "delta": {"content": delta}}],
                    }
                    yield f"data: {json.dumps(chunk)}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(event_stream(), media_type="text/event-stream")

    # ── /v1/audio/transcriptions ──────────────────────────────────────────────
    @api.post("/v1/audio/transcriptions")
    async def transcribe(
        request: Request,
        file: UploadFile = File(...),
        language: str = Form("ha"),
    ):
        check_bearer(request.headers.get("Authorization"), service.api_key)

        if language not in service.asr:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported language '{language}'. Use: {list(service.asr)}",
            )

        audio_bytes = await file.read()
        if not audio_bytes:
            raise HTTPException(status_code=400, detail="file is empty")

        ext = (file.filename or "audio.ogg").rsplit(".", 1)[-1].lower()

        try:
            wav_bytes = to_16k_mono_wav(audio_bytes, src_format=ext)
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr.decode(errors="replace")[-500:]
            raise HTTPException(
                status_code=422, detail=f"Audio conversion failed: {detail}"
            ) from exc

        import soundfile as sf

        asr_pipe = service.asr[language]
        texts: list[str] = []
        total_duration = 0.0

        for chunk in chunk_audio(wav_bytes):
            with io.BytesIO(chunk) as buf:
                samples, sr = sf.read(buf, dtype="float32")
            total_duration += len(samples) / sr
            result = asr_pipe({"array": samples, "sampling_rate": sr})
            text = (result.get("text") or "").strip()
            if text:
                texts.append(text)

        return JSONResponse({
            "text": " ".join(texts),
            "language": language,
            "duration_seconds": round(total_duration, 2),
        })

    return api


# ── Model loading ─────────────────────────────────────────────────────────────

def load_models(cache_dir: str, hf_token: str, api_key: str):
    """
    Download (if needed) and load the LLM and all four ASR models.

    Returns an object with the attributes `build_api` expects.
    """
    import torch
    from huggingface_hub import snapshot_download
    from transformers import AutoTokenizer
    from transformers import pipeline as hf_pipeline
    from vllm import AsyncEngineArgs, AsyncLLMEngine

    class Service:
        pass

    service = Service()

    # ── LLM weights ───────────────────────────────────────────────────────────
    llm_local = f"{cache_dir}/llm"
    if not os.path.exists(f"{llm_local}/config.json"):
        snapshot_download(
            LLM_REPO,
            local_dir=llm_local,
            token=hf_token,
            ignore_patterns=["*.msgpack", "*.h5", "flax_model*"],
        )

    # ── vLLM engine ───────────────────────────────────────────────────────────
    engine_args = AsyncEngineArgs(
        model=llm_local,
        dtype="bfloat16",
        max_model_len=MAX_MODEL_LEN,
        # Weights alone are 15 GiB; below ~0.75 the engine will not start.
        gpu_memory_utilization=0.84,
        trust_remote_code=False,
    )
    service.llm = AsyncLLMEngine.from_engine_args(engine_args)

    # Load once — applying the chat template per request would otherwise
    # re-read the tokenizer from disk.
    service.tokenizer = AutoTokenizer.from_pretrained(llm_local)

    # ── ASR pipelines ─────────────────────────────────────────────────────────
    device = "cuda" if torch.cuda.is_available() else "cpu"
    # fp16 halves each Whisper Small from ~1 GiB to ~0.45 GiB.
    asr_dtype = torch.float16 if device == "cuda" else torch.float32
    service.asr = {}
    for lang_code, repo in ASR_REPOS.items():
        local_dir = f"{cache_dir}/asr-{lang_code}"
        if not os.path.exists(f"{local_dir}/config.json"):
            snapshot_download(repo, local_dir=local_dir, token=hf_token)
        service.asr[lang_code] = hf_pipeline(
            "automatic-speech-recognition",
            model=local_dir,
            device=device,
            dtype=asr_dtype,  # `torch_dtype` is deprecated in transformers 5.x
        )

    service.api_key = api_key
    return service
