// Command voicechat demonstrates the natlas Go client: a streamed chat, then
// a voice round trip if an audio file is supplied.
//
//	export NATLAS_BASE_URL=https://your-gateway.modal.run
//	export NATLAS_API_KEY=your_api_key
//	go run ./examples/voicechat                      # streamed chat only
//	go run ./examples/voicechat recording.m4a        # chat + voice round trip
package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/Erhabor-Fona/natlas-mobile/packages/go/natlas"
)

func main() {
	baseURL := os.Getenv("NATLAS_BASE_URL")
	apiKey := os.Getenv("NATLAS_API_KEY")
	if baseURL == "" || apiKey == "" {
		log.Fatal("set NATLAS_BASE_URL and NATLAS_API_KEY")
	}

	client := natlas.New(baseURL, apiKey, natlas.WithTimeout(3*time.Minute))
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	// ── Health ────────────────────────────────────────────────────────────
	health, err := client.Health(ctx)
	if err != nil {
		log.Fatalf("gateway unreachable: %v", err)
	}
	fmt.Printf("gateway %s · llm %s · %d ASR models\n\n",
		health.Status, health.Models.LLM, len(health.Models.ASR))

	// ── Streamed chat ─────────────────────────────────────────────────────
	fmt.Print("Hausa > ")
	err = client.ChatStream(ctx, &natlas.ChatRequest{
		Messages:  []natlas.Message{natlas.UserMessage("Sannu! Gaya mini game da Kano.")},
		Language:  natlas.Hausa,
		MaxTokens: 256,
	}, func(delta string) error {
		fmt.Print(delta)
		return nil
	})
	if err != nil {
		handleErr(err)
	}
	fmt.Print("\n\n")

	// ── Voice round trip ──────────────────────────────────────────────────
	if len(os.Args) < 2 {
		fmt.Println("(pass an audio file path to try the voice round trip)")
		return
	}

	path := os.Args[1]
	audio, err := os.ReadFile(path)
	if err != nil {
		log.Fatalf("read %s: %v", path, err)
	}

	result, err := client.VoiceChat(ctx, &natlas.VoiceChatRequest{
		Audio:     audio,
		Language:  natlas.Hausa,
		Filename:  path,
		MaxTokens: 256,
	})
	if err != nil {
		handleErr(err)
	}

	fmt.Printf("heard (%.1fs): %s\n\n", result.Transcript.DurationSeconds, result.Transcript.Text)
	fmt.Printf("reply: %s\n", result.Reply)
}

func handleErr(err error) {
	switch {
	case errors.Is(err, natlas.ErrUnauthorized):
		log.Fatal("bad API key — check NATLAS_API_KEY")
	case errors.Is(err, natlas.ErrRateLimited):
		log.Fatal("rate limited — back off and retry")
	default:
		var apiErr *natlas.APIError
		if errors.As(err, &apiErr) {
			log.Fatalf("gateway returned %d: %s", apiErr.StatusCode, apiErr.Detail)
		}
		log.Fatal(err)
	}
}
