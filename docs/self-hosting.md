# Self-hosting the gateway

There is no public hosted N-ATLaS API. To use any SDK in this repo you run the
gateway yourself — it puts the LLM and all four ASR models behind one
OpenAI-compatible base URL.

Two options: **Modal** (recommended — scales to zero, no GPU of your own) or
**Docker Compose** (if you have a local NVIDIA GPU).

---

## Before either option: model access

All five Hugging Face repos are gated. You must accept the terms on each one
with your own HF account, or downloads fail with `401`:

- [NCAIR1/N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS)
- [NCAIR1/Hausa-ASR](https://huggingface.co/NCAIR1/Hausa-ASR)
- [NCAIR1/Igbo-ASR](https://huggingface.co/NCAIR1/Igbo-ASR)
- [NCAIR1/Yoruba-ASR](https://huggingface.co/NCAIR1/Yoruba-ASR)
- [NCAIR1/NigerianAccentedEnglish](https://huggingface.co/NCAIR1/NigerianAccentedEnglish)

Then create a read token at
[huggingface.co/settings/tokens](https://huggingface.co/settings/tokens).

Check access before you deploy, so a failure is cheap to diagnose:

```bash
pip install huggingface_hub
python -c "
from huggingface_hub import model_info
for repo in ['NCAIR1/N-ATLaS','NCAIR1/Hausa-ASR','NCAIR1/Igbo-ASR',
             'NCAIR1/Yoruba-ASR','NCAIR1/NigerianAccentedEnglish']:
    model_info(repo, token='hf_...')
    print('ok', repo)
"
```

Note the licence terms: 1 000 active end-users per rolling 30 days, attribution
mandatory, no commercial deployment without a separate licence. See
[NOTICE](../NOTICE).

---

## Option 1 — Modal (recommended)

Scales to zero between requests, so an idle gateway costs nothing. One A10G
holds the LLM and all four ASR models.

### 1. Install and authenticate

```bash
pip install modal
modal setup
```

### 2. Create the secret

The gateway reads `HF_TOKEN` and `NATLAS_API_KEY` from one Modal secret.
`NATLAS_API_KEY` is yours to invent — it is the bearer token your apps will
present.

```bash
modal secret create natlas-api \
  HF_TOKEN=hf_your_token_here \
  NATLAS_API_KEY=$(openssl rand -hex 32)
```

Print the key you just generated so you can paste it into the demo app:

```bash
modal secret list                     # confirms it exists
# To see the value, check the Modal dashboard — secrets are write-only via CLI.
```

Generate it separately if you would rather keep a copy:

```bash
export NATLAS_API_KEY=$(openssl rand -hex 32)
echo "$NATLAS_API_KEY"                # save this
modal secret create natlas-api \
  HF_TOKEN=hf_your_token_here \
  NATLAS_API_KEY="$NATLAS_API_KEY"
```

### 3. Deploy

```bash
modal deploy serve/modal_app.py
```

Modal prints the app URL. That is your `NATLAS_BASE_URL`.

### 4. Verify

```bash
export NATLAS_BASE_URL=https://your-app.modal.run

curl "$NATLAS_BASE_URL/health"
```

The first call is a cold start: the container downloads ~16 GB of weights into
the persistent volume and loads five models onto the GPU. Budget **5–10 minutes
for the very first request**, and 30–90 seconds for cold starts after that
(weights are cached in the volume, so only loading remains).

```bash
curl -X POST "$NATLAS_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $NATLAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Sannu!"}],"language":"ha"}'
```

### Cold starts and demo day

`scaledown_window=300` keeps the container warm for 5 minutes after the last
request (20 minutes is the maximum Modal allows). For a live demo, either:

- **Warm it up** — hit `/health` a few minutes before you present, then keep a
  request going every couple of minutes.
- **Pin a container** — set `min_containers=1` in the `@app.cls` decorator.
  This holds a GPU permanently, which costs money while idle but removes the
  cold start. Worth it on the day, not before.

```python
@app.cls(
    gpu="A10G",
    # …
    min_containers=1,   # demo day only
)
```

### Costs

An A10G is roughly $1.10/hour on Modal while a container is running. Scaling to
zero means an idle gateway is free apart from volume storage (a few cents a
month for ~16 GB). Pinning a container for a day costs about $26.

---

## Option 2 — Docker Compose

For a local NVIDIA GPU (24 GB or more recommended — the LLM in bfloat16 wants
~16 GB and the ASR models another ~4 GB).

```bash
cd serve
cp ../.env.example .env
# Fill in HF_TOKEN and NATLAS_API_KEY

docker compose up --build
```

The gateway listens on `http://localhost:8000`, so:

```bash
export NATLAS_BASE_URL=http://localhost:8000
curl "$NATLAS_BASE_URL/health"
```

Weights are cached in a named volume, so the long download happens only once.

Requires the [NVIDIA Container
Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

---

## Pointing an SDK at it

```bash
export NATLAS_BASE_URL=https://your-app.modal.run
export NATLAS_API_KEY=your_key
```

**Flutter** — enter both in the demo app's first-run settings screen, or:

```dart
final client = NAtlasClient(baseUrl: '…', apiKey: '…');
```

**Go**

```go
client := natlas.New(os.Getenv("NATLAS_BASE_URL"), os.Getenv("NATLAS_API_KEY"))
```

**Rust**

```rust
let client = NAtlasClient::new(
    std::env::var("NATLAS_BASE_URL")?,
    std::env::var("NATLAS_API_KEY")?,
);
```

---

## Troubleshooting

**`401` from Hugging Face during startup** — the token lacks access to one of
the five repos. Accept the terms on each model card, then redeploy.

**`401` from the gateway** — your bearer token does not match the
`NATLAS_API_KEY` in the Modal secret. Secrets are read at container start, so
update the secret *and* redeploy.

**CUDA out of memory** — `gpu_memory_utilization=0.6` in `modal_app.py` reserves
40% of VRAM for the ASR models. Lower it if vLLM still cannot fit, or move to a
larger GPU (`gpu="A100"`).

**`422` on transcription** — ffmpeg could not read the upload. Check the
filename extension matches the actual container format; the gateway uses the
extension as a hint.

**Transcription returns plausible nonsense** — you sent the wrong `language`.
The ASR models are per-language, not multilingual, so a Hausa model given
Yorùbá audio produces confident garbage rather than an error.

**Requests hang around 60 seconds** — that is the default client timeout, not
the gateway. Raise it: `timeout:` in Flutter, `WithTimeout` in Go, `.timeout()`
in Rust.

---

## When an official API arrives

If NCAIR publishes a hosted endpoint, nothing in the SDKs changes — swap
`baseUrl` and `apiKey` for the official ones and delete your deployment. The
whole point of keeping the gateway behind a base URL is that it is replaceable.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
