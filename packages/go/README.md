# natlas-go

Go client for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS) — Nigeria's
sovereign multilingual LLM. Hausa · Igbo · Yorùbá · Nigerian English.

Zero dependencies outside the standard library.

## Install

```bash
go get github.com/Erhabor-Fona/natlas-mobile/packages/go/natlas
```

```go
import "github.com/Erhabor-Fona/natlas-mobile/packages/go/natlas"
```

## Use

```go
client := natlas.New(os.Getenv("NATLAS_BASE_URL"), os.Getenv("NATLAS_API_KEY"))
```

### Chat

```go
resp, err := client.Chat(ctx, &natlas.ChatRequest{
    Messages: []natlas.Message{natlas.UserMessage("Sannu! Yaya aiki?")},
    Language: natlas.Hausa,
})
if err != nil {
    return err
}
fmt.Println(resp.Content())
```

### Streaming chat

```go
err := client.ChatStream(ctx, &natlas.ChatRequest{
    Messages: []natlas.Message{natlas.UserMessage("Kedụ?")},
    Language: natlas.Igbo,
}, func(delta string) error {
    fmt.Print(delta)
    return nil
})
```

Return a non-nil error from the callback to abort the stream early; cancelling
`ctx` stops it too.

### Speech-to-text

```go
audio, _ := os.ReadFile("recording.m4a")

result, err := client.Transcribe(ctx, &natlas.TranscribeRequest{
    Audio:    audio,
    Language: natlas.Hausa,
    Filename: "recording.m4a",
})
fmt.Println(result.Text)
```

### Voice chat (transcribe + reply in one call)

```go
result, err := client.VoiceChat(ctx, &natlas.VoiceChatRequest{
    Audio:    audio,
    Language: natlas.Hausa,
    History:  previousMessages,
})
fmt.Println(result.Transcript.Text)  // what the user said
fmt.Println(result.Reply)            // what N-ATLaS replied
```

## Errors

Non-2xx responses return `*natlas.APIError`, which also matches the package
sentinels through `errors.Is`:

```go
resp, err := client.Chat(ctx, req)
switch {
case errors.Is(err, natlas.ErrUnauthorized):
    log.Fatal("bad API key")
case errors.Is(err, natlas.ErrRateLimited):
    time.Sleep(backoff)
case err != nil:
    var apiErr *natlas.APIError
    if errors.As(err, &apiErr) {
        log.Printf("gateway said %d: %s", apiErr.StatusCode, apiErr.Detail)
    }
}
```

## Options

```go
client := natlas.New(baseURL, apiKey,
    natlas.WithTimeout(5*time.Minute),        // long generations
    natlas.WithHTTPClient(myInstrumentedClient), // tracing, retries, pooling
)
```

## Languages

| Constant | Code | Language |
|---|---|---|
| `natlas.Hausa` | `ha` | Hausa |
| `natlas.Igbo` | `ig` | Igbo |
| `natlas.Yoruba` | `yo` | Yorùbá |
| `natlas.English` | `en` | Nigerian English |

## Audio formats

Pass raw bytes in any format `ffmpeg` can read — ogg/opus, m4a, mp3, wav,
webm, flac. The gateway converts to 16 kHz mono WAV and chunks recordings
longer than 28 seconds, so you do not need to pre-process on the client.

## Tests

```bash
go test ./...
```

Tests assert against `shared/fixtures/` (symlinked as `natlas/testdata`), the
same payloads the Flutter and Rust SDKs use.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
