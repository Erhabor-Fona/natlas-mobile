#!/usr/bin/env python3
"""
natlas-mobile · serve/smoke_test.py
====================================
End-to-end check of a deployed N-ATLaS gateway. Exercises every endpoint the
SDKs rely on and prints one pass/fail line each.

    export NATLAS_BASE_URL=https://your-app.modal.run
    export NATLAS_API_KEY=...

    python3 serve/smoke_test.py                   # synthetic audio
    python3 serve/smoke_test.py recording.m4a     # your own recording
    python3 serve/smoke_test.py --all-languages   # chat in all four

Stdlib only — no pip install needed.

Notes:
  * Modal caps HTTP requests at 150 s and then 303-redirects to a result URL.
    urllib follows redirects, so a cold start just looks slow (2-4 minutes).
  * With synthetic audio the transcript is meaningless by design. That test
    checks the plumbing (ffmpeg conversion, chunking, ASR dispatch, response
    shape), not transcription quality. Pass a real recording to judge that.

Exit code is 0 only if every test passes.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import struct
import sys
import time
import urllib.error
import urllib.request
import uuid
import wave

LANGUAGES = {
    "ha": ("Hausa", "Sannu! Yaya aiki?"),
    "ig": ("Igbo", "Kedụ! Kedu ka ị mere?"),
    "yo": ("Yorùbá", "Báwo ni! Ṣé dáadáa ni?"),
    "en": ("Nigerian English", "Hello! How far?"),
}

TIMEOUT = 900  # generous: a cold start loads 15 GiB plus four ASR models

_COLOR = sys.stdout.isatty()
_OK = "\033[32mPASS\033[0m" if _COLOR else "PASS"
_NO = "\033[31mFAIL\033[0m" if _COLOR else "FAIL"
_SKIP = "\033[33mSKIP\033[0m" if _COLOR else "SKIP"

results: list[tuple[str, bool]] = []


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def _call(method: str, url: str, *, headers=None, data=None, timeout=TIMEOUT):
    """Return (status, body_bytes). Non-2xx comes back rather than raising."""
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def _multipart(fields: dict, field: str, filename: str,
               content: bytes, content_type: str):
    boundary = uuid.uuid4().hex
    body = io.BytesIO()
    for key, value in fields.items():
        body.write(f"--{boundary}\r\n".encode())
        body.write(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        body.write(f"{value}\r\n".encode())
    body.write(f"--{boundary}\r\n".encode())
    body.write(
        f'Content-Disposition: form-data; name="{field}"; '
        f'filename="{filename}"\r\n'.encode()
    )
    body.write(f"Content-Type: {content_type}\r\n\r\n".encode())
    body.write(content)
    body.write(f"\r\n--{boundary}--\r\n".encode())
    return body.getvalue(), f"multipart/form-data; boundary={boundary}"


def _synthetic_wav(seconds: float = 2.0, rate: int = 16000) -> bytes:
    """A quiet 220 Hz tone — 16 kHz mono WAV, the format the ASR models want."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for i in range(int(rate * seconds)):
            frames += struct.pack("<h", int(3000 * math.sin(2 * math.pi * 220 * i / rate)))
        w.writeframes(bytes(frames))
    return buf.getvalue()


def _mime_for(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return {
        "ogg": "audio/ogg", "opus": "audio/ogg", "mp3": "audio/mpeg",
        "m4a": "audio/m4a", "mp4": "audio/m4a", "aac": "audio/m4a",
        "wav": "audio/wav", "webm": "audio/webm", "flac": "audio/flac",
    }.get(ext, "application/octet-stream")


def _record(name: str, ok: bool, detail: str = "", elapsed: float | None = None):
    results.append((name, ok))
    stamp = f" [{elapsed:.1f}s]" if elapsed is not None else ""
    print(f"  {_OK if ok else _NO}  {name}{stamp}")
    if detail:
        for line in detail.splitlines():
            print(f"        {line}")


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_health(base: str) -> bool:
    print("\nhealth")
    start = time.monotonic()
    try:
        status, body = _call("GET", f"{base}/health")
    except Exception as exc:
        _record("GET /health", False, f"{type(exc).__name__}: {exc}")
        return False
    elapsed = time.monotonic() - start

    if status != 200:
        detail = body[:300].decode(errors="replace")
        _record("GET /health", False, f"HTTP {status}: {detail}", elapsed)
        return False

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        _record("GET /health", False, f"not JSON: {body[:200].decode(errors='replace')}", elapsed)
        return False

    asr = payload.get("models", {}).get("asr", [])
    ok = payload.get("status") == "ok" and len(asr) == 4
    _record(
        "GET /health", ok,
        f"status={payload.get('status')}  llm={payload.get('models', {}).get('llm')}\n"
        f"asr models={len(asr)}"
        + ("" if ok else "  <- expected 4"),
        elapsed,
    )
    return ok


def test_auth(base: str) -> None:
    print("\nauth")
    body = json.dumps({
        "messages": [{"role": "user", "content": "hi"}],
        "language": "en", "max_tokens": 4,
    }).encode()
    start = time.monotonic()
    status, raw = _call("POST", f"{base}/v1/chat/completions", headers={
        "Authorization": "Bearer definitely-not-the-key",
        "Content-Type": "application/json",
    }, data=body)
    elapsed = time.monotonic() - start
    _record(
        "bad key rejected with 401", status == 401,
        f"got HTTP {status}" + ("" if status == 401 else f": {raw[:200].decode(errors='replace')}"),
        elapsed,
    )


def test_chat(base: str, key: str, lang: str) -> None:
    name, prompt = LANGUAGES[lang]
    body = json.dumps({
        "messages": [{"role": "user", "content": prompt}],
        "language": lang,
        "max_tokens": 64,
    }).encode()

    start = time.monotonic()
    status, raw = _call("POST", f"{base}/v1/chat/completions", headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }, data=body)
    elapsed = time.monotonic() - start

    label = f"chat [{lang}] {name}"
    if status != 200:
        _record(label, False, f"HTTP {status}: {raw[:300].decode(errors='replace')}", elapsed)
        return

    try:
        payload = json.loads(raw)
        content = payload["choices"][0]["message"]["content"]
    except (json.JSONDecodeError, KeyError, IndexError) as exc:
        snippet = raw[:200].decode(errors="replace")
        _record(label, False, f"unexpected shape ({exc}): {snippet}", elapsed)
        return

    usage = payload.get("usage", {})
    tokens_in = usage.get("prompt_tokens", "?")
    tokens_out = usage.get("completion_tokens", "?")
    ok = bool(content.strip())
    _record(
        label, ok,
        f"prompt:  {prompt}\n"
        f"reply:   {content.strip()[:200] or '(empty)'}\n"
        f"tokens:  {tokens_in} in / {tokens_out} out",
        elapsed,
    )


def test_stream(base: str, key: str, lang: str = "ha") -> None:
    name, prompt = LANGUAGES[lang]
    body = json.dumps({
        "messages": [{"role": "user", "content": prompt}],
        "language": lang,
        "max_tokens": 64,
        "stream": True,
    }).encode()

    req = urllib.request.Request(
        f"{base}/v1/chat/completions", data=body, method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
    )

    start = time.monotonic()
    deltas: list[str] = []
    saw_done = False
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            if resp.status != 200:
                _record(f"stream [{lang}]", False, f"HTTP {resp.status}")
                return
            for line in resp:
                text = line.decode("utf-8", errors="replace").strip()
                if not text.startswith("data: "):
                    continue
                data = text[6:].strip()
                if data == "[DONE]":
                    saw_done = True
                    break
                try:
                    chunk = json.loads(data)
                    piece = chunk["choices"][0]["delta"].get("content", "")
                    if piece:
                        deltas.append(piece)
                except (json.JSONDecodeError, KeyError, IndexError):
                    continue
    except Exception as exc:
        _record(f"stream [{lang}]", False, f"{type(exc).__name__}: {exc}")
        return

    elapsed = time.monotonic() - start
    assembled = "".join(deltas)
    ok = len(deltas) > 1 and bool(assembled.strip()) and saw_done
    detail = (
        f"chunks:  {len(deltas)}\n"
        f"[DONE]:  {'yes' if saw_done else 'NO - stream ended without sentinel'}\n"
        f"text:    {assembled.strip()[:200] or '(empty)'}"
    )
    if len(deltas) == 1:
        detail += "\n         only one chunk - not actually streaming?"
    _record(f"stream [{lang}]", ok, detail, elapsed)


def test_transcribe(base: str, key: str, audio_path: str | None, lang: str = "ha") -> None:
    if audio_path:
        try:
            with open(audio_path, "rb") as f:
                content = f.read()
        except OSError as exc:
            _record(f"transcribe [{lang}]", False, f"cannot read {audio_path}: {exc}")
            return
        filename = os.path.basename(audio_path)
        synthetic = False
    else:
        content = _synthetic_wav()
        filename = "synthetic.wav"
        synthetic = True

    data, content_type = _multipart(
        {"language": lang}, "file", filename, content, _mime_for(filename)
    )

    start = time.monotonic()
    status, raw = _call("POST", f"{base}/v1/audio/transcriptions", headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": content_type,
    }, data=data)
    elapsed = time.monotonic() - start

    label = f"transcribe [{lang}] {filename}"
    if status != 200:
        _record(label, False, f"HTTP {status}: {raw[:300].decode(errors='replace')}", elapsed)
        return

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        _record(label, False, f"not JSON: {raw[:200].decode(errors='replace')}", elapsed)
        return

    has_shape = "text" in payload and "language" in payload
    lang_ok = payload.get("language") == lang
    ok = has_shape and lang_ok

    detail = (
        f"text:     {payload.get('text', '')[:200] or '(empty)'}\n"
        f"language: {payload.get('language')}" + ("" if lang_ok else f"  <- expected {lang}") + "\n"
        f"duration: {payload.get('duration_seconds')}s"
    )
    if synthetic:
        detail += "\n          synthetic tone - gibberish text here is expected and fine"
    _record(label, ok, detail, elapsed)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description="Smoke-test a N-ATLaS gateway.")
    parser.add_argument("audio", nargs="?", help="audio file for transcription")
    parser.add_argument("--all-languages", action="store_true",
                        help="run chat in all four languages instead of Hausa only")
    parser.add_argument("--base-url", default=os.environ.get("NATLAS_BASE_URL"))
    parser.add_argument("--api-key", default=os.environ.get("NATLAS_API_KEY"))
    args = parser.parse_args()

    if not args.base_url or not args.api_key:
        print("Set NATLAS_BASE_URL and NATLAS_API_KEY (or pass --base-url / --api-key).",
              file=sys.stderr)
        return 2

    base = args.base_url.rstrip("/")
    print(f"gateway: {base}")
    print("A cold container takes 2-4 minutes on the first call. Modal 303-redirects")
    print("past its 150 s cap and urllib follows that, so slow is not broken.")

    if not test_health(base):
        print("\n/health failed — skipping the rest, nothing downstream can work.")
        return 1

    test_auth(base)

    print("\nchat")
    langs = list(LANGUAGES) if args.all_languages else ["ha"]
    for lang in langs:
        test_chat(base, args.api_key, lang)

    print("\nstreaming")
    test_stream(base, args.api_key)

    print("\ntranscription")
    test_transcribe(base, args.api_key, args.audio)

    passed = sum(1 for _, ok in results if ok)
    total = len(results)
    print(f"\n{'─' * 60}")
    print(f"{passed}/{total} passed")
    if passed < total:
        print("failed: " + ", ".join(name for name, ok in results if not ok))
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
