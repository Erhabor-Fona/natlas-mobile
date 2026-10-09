# Go

Full API documentation lives in the package README:
**[packages/go/README.md](../packages/go/README.md)**

This page covers what is specific to running N-ATLaS in Go services.

## Install

```bash
go get github.com/Erhabor-Fona/natlas-mobile/packages/go/natlas
```

## Where this fits

The Go client is for infrastructure around N-ATLaS rather than for end-user
apps: a backend that proxies mobile traffic and holds the API key, a CLI for
batch transcription, a translation worker pulling from a queue, an uptime
probe.

The commonest shape is the proxy a mobile app should talk to instead of holding
a key itself:

```go
func handleChat(w http.ResponseWriter, r *http.Request) {
    // Authenticate YOUR user, enforce YOUR rate limits, then:
    resp, err := natlasClient.Chat(r.Context(), &natlas.ChatRequest{
        Messages: userMessages,
        Language: natlas.Hausa,
    })
    // …
}
```

That gives you one place for rate limiting, which matters given the model
licence's 1 000 active end-user cap per rolling 30 days.

## Context and cancellation

Every method takes a `context.Context` and honours it. Pass the request context
through so a disconnected client stops work server-side:

```go
ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
defer cancel()

resp, err := client.Chat(ctx, req)
```

For streaming, cancelling the context stops the loop between chunks.

## Streaming

`ChatStream` is callback-based rather than channel-based, so backpressure and
error propagation are explicit:

```go
err := client.ChatStream(ctx, req, func(delta string) error {
    if _, err := w.Write([]byte(delta)); err != nil {
        return err   // client disconnected — abort the stream
    }
    w.(http.Flusher).Flush()
    return nil
})
```

Returning a non-nil error aborts and surfaces that error from `ChatStream`.

To re-emit as SSE to your own clients:

```go
w.Header().Set("Content-Type", "text/event-stream")
w.Header().Set("Cache-Control", "no-cache")

err := client.ChatStream(ctx, req, func(delta string) error {
    payload, _ := json.Marshal(map[string]string{"delta": delta})
    fmt.Fprintf(w, "data: %s\n\n", payload)
    w.(http.Flusher).Flush()
    return nil
})
fmt.Fprint(w, "data: [DONE]\n\n")
```

## Concurrency

`*Client` is safe for concurrent use — it wraps an `*http.Client`, which pools
connections. Create one per process, not per request.

The gateway is the bottleneck, not the client: a single A10G serves one vLLM
engine. Bound your own concurrency rather than letting requests pile up:

```go
sem := make(chan struct{}, 4)

sem <- struct{}{}
defer func() { <-sem }()
resp, err := client.Chat(ctx, req)
```

## Timeouts

The default is 60 seconds, which is not enough for a cold start on Modal.

```go
client := natlas.New(baseURL, apiKey, natlas.WithTimeout(5*time.Minute))
```

Better: probe `Health` at startup so the gateway is warm before real traffic,
and set a shorter timeout for user-facing requests.

```go
if _, err := client.Health(ctx); err != nil {
    log.Printf("gateway cold or unreachable: %v", err)
}
```

## Instrumenting

`WithHTTPClient` takes any `*http.Client`, so tracing, retries, and metrics go
in a `RoundTripper`:

```go
client := natlas.New(baseURL, apiKey,
    natlas.WithHTTPClient(&http.Client{
        Timeout:   5 * time.Minute,
        Transport: otelhttp.NewTransport(http.DefaultTransport),
    }),
)
```

## Batch transcription

Transcription is CPU/GPU-bound on the gateway, so parallelism past a couple of
workers buys nothing on a single A10G:

```go
sem := make(chan struct{}, 2)
var wg sync.WaitGroup

for _, path := range paths {
    wg.Add(1)
    go func(path string) {
        defer wg.Done()
        sem <- struct{}{}
        defer func() { <-sem }()

        audio, err := os.ReadFile(path)
        if err != nil {
            log.Printf("%s: %v", path, err)
            return
        }

        result, err := client.Transcribe(ctx, &natlas.TranscribeRequest{
            Audio:    audio,
            Language: natlas.Hausa,
            Filename: path,
        })
        if err != nil {
            log.Printf("%s: %v", path, err)
            return
        }
        log.Printf("%s: %s", path, result.Text)
    }(path)
}
wg.Wait()
```

Recordings of any length work — the gateway chunks anything over 28 seconds.

## Errors

```go
resp, err := client.Chat(ctx, req)
switch {
case errors.Is(err, natlas.ErrUnauthorized):
    // Bad key — do not retry.
case errors.Is(err, natlas.ErrRateLimited):
    // Back off.
case errors.Is(err, natlas.ErrBadRequest):
    // 400 or 422 — your request is wrong, do not retry.
case err != nil:
    var apiErr *natlas.APIError
    if errors.As(err, &apiErr) {
        log.Printf("gateway %d: %s", apiErr.StatusCode, apiErr.Detail)
    }
}
```

Transport failures wrap the underlying `*url.Error`, so `errors.Is(err,
context.DeadlineExceeded)` works for timeouts.

## Example

[`packages/go/examples/voicechat`](../packages/go/examples/voicechat/main.go)
is a runnable program covering health, streaming, and a voice round trip:

```bash
export NATLAS_BASE_URL=https://your-gateway.modal.run
export NATLAS_API_KEY=your_key
go run ./examples/voicechat recording.m4a
```

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
