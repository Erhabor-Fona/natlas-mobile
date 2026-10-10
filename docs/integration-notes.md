# N-ATLaS integration notes

Things we learned building against N-ATLaS that are not written down on the
model cards, and that cost us time. Published so they cost you less.

Measured in October 2026 against `NCAIR1/N-ATLaS` and the four `NCAIR1`
ASR models, served with vLLM 0.31 on a single NVIDIA A10G.

---

## 1. The ASR models are per-language, not multilingual

This is the single most important thing on this page.

N-ATLaS ships **four separate Whisper Small fine-tunes**, one per language:

| Language | Model |
|---|---|
| Hausa | `NCAIR1/Hausa-ASR` |
| Igbo | `NCAIR1/Igbo-ASR` |
| Yorùbá | `NCAIR1/Yoruba-ASR` |
| Nigerian English | `NCAIR1/NigerianAccentedEnglish` |

They are **not** interchangeable, and there is no language-detection front
door. Feed Yorùbá audio to the Hausa model and you do not get an error or a
low confidence score — you get fluent, plausible, completely wrong Hausa
text. The failure is silent and it looks like success.

Consequences for anything you build:

- The language must be chosen **before** the audio is captured, and it must
  be part of your transcription request. It cannot be inferred afterwards.
- Load all four if you want to switch languages without a cold start. At
  fp16 each one is about 0.45 GiB, so all four cost roughly 1.8 GiB — cheap
  enough to keep co-resident beside the 8B chat model.
- If your UI lets someone change language mid-session, discard the
  conversation or at minimum stop sending prior turns. The chat model will
  otherwise keep answering in the previous language.

All four inherit Whisper's constraints: **16 kHz mono**, and a **30-second
receptive window**. Anything longer must be chunked client- or server-side;
the model will not tell you it truncated.

## 2. The chat template requires `date_string`

N-ATLaS is a Llama-3 8B fine-tune and uses the Llama-3 chat template, which
references a `date_string` variable. Omit it and template rendering fails
with an error that points at the template internals rather than at the
missing variable, which makes it look like a tokenizer or version problem.

Pass it explicitly when applying the chat template. Context length is
**8092 tokens**, which is the budget for system prompt, history and reply
combined.

## 3. All five repositories are gated

`N-ATLaS` and all four ASR models sit behind Hugging Face's "agree to share
your contact information" gate. Approval is automatic, but you must accept
on **each of the five repositories individually**, and any machine pulling
weights needs an `HF_TOKEN` from an account that has accepted.

This bites hardest in CI and in container builds, where the download fails
as a 401 on a URL that looks public when you open it in a logged-in
browser.

## 4. Serving: all five models fit on one A10G

Useful if you are self-hosting rather than calling a shared endpoint.

An A10G has 24 GB, of which about 22.5 GiB is usable. The 8B weights are
**15.0 GiB** in fp16. The number that matters is vLLM's
`gpu_memory_utilization`, which is a fraction of **total** GPU memory, not
of what is left after weights load:

| `gpu_memory_utilization` | Result |
|---|---|
| 0.60 | `Available KV cache memory: -3.25 GiB` — engine refuses to start |
| 0.84 | 2.05 GiB KV cache — works, four ASR models co-resident |

At 0.60 the budget is 14.4 GiB, which is less than the weights alone, and
the error arrives as a negative cache size rather than as "not enough
memory". If you see a negative KV cache figure, this is why.

Two more vLLM 0.31 details:

- It defaults to **FlashInfer** for top-p/top-k sampling, which JIT-compiles
  its kernels and therefore needs `nvcc`. On a slim base image with no CUDA
  toolkit this fails inside `get_cuda_path`. Set
  `VLLM_USE_FLASHINFER_SAMPLER=0` unless you have shipped the toolkit.
- `AsyncLLMEngine` is now an alias for `AsyncLLM`. `from_engine_args`,
  positional `generate(prompt, sampling_params, request_id)` and
  `vllm.utils.random_uuid` all still work.

On transformers 5.x, the ASR pipeline wants `dtype=`; `torch_dtype=` is
deprecated. The pipeline casts input features to the model's dtype, so
feeding fp32 numpy into an fp16 model is safe.

Cold start from scratch is roughly 100 seconds — five models to load from
disk. Budget for it in client timeouts, and keep one container warm for
anything with an audience.

## 5. Tone marks are semantic, and phone keyboards cannot produce them

Yorùbá and Igbo mark tone with diacritics that change meaning, not just
spelling. N-ATLaS answers noticeably better on correctly marked input than
on the same sentence unmarked — which matters because **most people typing
these languages on a phone type them unmarked**, since no stock mobile
keyboard offers the marks.

There is a second, sharper problem underneath. The combinations these
languages need — a dot-below vowel *carrying* a tone mark, like `ẹ́` or `ị̀` —
have **no precomposed Unicode codepoint at all**, not even after NFC
normalisation. They can only be represented as a base letter followed by a
combining accent:

```
ẹ́  =  U+1EB9 (ẹ)  +  U+0301 (combining acute)
```

So any input affordance you build has to insert combining marks, not just
pick from a list of precomposed characters. Render a standalone combining
mark on a dotted circle (`U+25CC`) so it is visible as a key label.

Hausa in Boko orthography is different again: it needs hooked consonants
(`ɓ ɗ ƙ ƴ`) and the modifier apostrophe `ʼ`, but standard written Hausa does
**not** mark tone, so tone keys are wrong there.

`natlas_flutter` ships `NAtlasDiacriticBar` for this, with per-language key
sets. If you are building your own, the key sets are the part worth copying.

## 6. Sampling temperature and reproducibility

At `temperature=0.7` the same prompt gives materially different answers
across runs — in our testing, one Hausa greeting returned both an idiomatic
reply and a grammatically odd one. For demos, benchmarks, or anything you
need to reproduce, drop to around **0.3**.

## 7. If you serve behind Modal

Modal's HTTP functions cap a response at **150 seconds**, then return a
`303` redirect to a result URL. Any client must follow redirects or it will
see a bare 303 and treat it as a failure — this surfaces as a cold-start
request "failing" while the warm ones succeed.

Also: `container_idle_timeout` is deprecated in favour of
`scaledown_window`.

## 8. Mobile capture, if you are recording on-device

Not N-ATLaS-specific, but it is where we lost the most time, and anyone
building a voice client will hit it.

On iOS, capture **WAV**. Compressed containers failed in two different ways:

- `opus` writes into a **CAF** container on iOS, not Ogg, whatever extension
  you give the file.
- `aacLc` produces an `.m4a` whose `moov` atom — the index, written at the
  *end* on finalisation — was missing, so every upload died at
  `moov atom not found`. Waiting for the file size to settle did not help.

WAV has no trailing index: a header followed by raw samples. A truncated
WAV still decodes to end-of-file instead of failing outright, and at 16 kHz
mono 16-bit it is already the ASR models' native format — about 32 KB/s, so
a ten-second clip is ~320 KB.

The diagnostic worth running first, rather than reasoning about what the
platform *ought* to write: dump the first 16 bytes of the file. `RIFF` at
offset 0 is WAV, `ftyp` at offset 4 is MP4/M4A, `caff` is CAF, `OggS` is
Ogg. That single check would have saved us three wrong theories.

---

## Licensing

N-ATLaS is **not** Apache-2.0. It is released under the Open-Source
Research and Innovation License (Awarri / FMCIDE), which requires
attribution, imposes share-alike on model derivatives, and **caps active
end-users at 1,000 per rolling 30-day period** without a separate
commercial licence. Read `NOTICE` in this repository for the full summary,
and the Terms of Use on each model card for the authoritative text.

Required attribution, in all public deployments:

> N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.

---

## Corrections welcome

These are findings from one build against one deployment, in October 2026.
If something here is wrong, out of date, or was fixed upstream, please open
an issue — the point of this page is that the next person does not have to
rediscover any of it.
