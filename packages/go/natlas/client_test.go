package natlas

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// loadFixture reads a shared fixture. testdata/ symlinks to shared/fixtures/
// so the Flutter, Go, and Rust SDKs assert against identical payloads.
func loadFixture(t *testing.T, name string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("load fixture %s: %v", name, err)
	}
	return data
}

func TestLanguage(t *testing.T) {
	t.Run("codes match the gateway contract", func(t *testing.T) {
		cases := map[Language]string{
			Hausa:   "ha",
			Igbo:    "ig",
			Yoruba:  "yo",
			English: "en",
		}
		for lang, code := range cases {
			if string(lang) != code {
				t.Errorf("Language(%v) = %q, want %q", lang, string(lang), code)
			}
		}
	})

	t.Run("ParseLanguage round-trips", func(t *testing.T) {
		for _, lang := range []Language{Hausa, Igbo, Yoruba, English} {
			got, err := ParseLanguage(string(lang))
			if err != nil {
				t.Fatalf("ParseLanguage(%q): %v", lang, err)
			}
			if got != lang {
				t.Errorf("ParseLanguage(%q) = %v, want %v", lang, got, lang)
			}
		}
	})

	t.Run("ParseLanguage rejects unknown codes", func(t *testing.T) {
		if _, err := ParseLanguage("fr"); err == nil {
			t.Error("ParseLanguage(\"fr\") succeeded, want error")
		}
	})

	t.Run("display names", func(t *testing.T) {
		if got := Yoruba.DisplayName(); got != "Yorùbá" {
			t.Errorf("Yoruba.DisplayName() = %q, want %q", got, "Yorùbá")
		}
		if got := English.DisplayName(); got != "Nigerian English" {
			t.Errorf("English.DisplayName() = %q", got)
		}
	})
}

func TestChat(t *testing.T) {
	t.Run("sends the documented request body", func(t *testing.T) {
		var sent map[string]any

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != "/v1/chat/completions" {
				t.Errorf("path = %q", r.URL.Path)
			}
			if got := r.Header.Get("Authorization"); got != "Bearer test_key" {
				t.Errorf("Authorization = %q", got)
			}
			body, _ := io.ReadAll(r.Body)
			if err := json.Unmarshal(body, &sent); err != nil {
				t.Fatalf("unmarshal sent body: %v", err)
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write(loadFixture(t, "chat_response.json"))
		}))
		defer srv.Close()

		client := New(srv.URL, "test_key")
		resp, err := client.Chat(context.Background(), &ChatRequest{
			Messages: []Message{UserMessage("Sannu! Yaya aiki?")},
			Language: Hausa,
		})
		if err != nil {
			t.Fatalf("Chat: %v", err)
		}

		if sent["language"] != "ha" {
			t.Errorf("language = %v, want ha", sent["language"])
		}
		if sent["stream"] != false {
			t.Errorf("stream = %v, want false", sent["stream"])
		}
		if !strings.Contains(resp.Content(), "Sannu da zuwa") {
			t.Errorf("Content() = %q", resp.Content())
		}
		if resp.TotalTokens() != 60 {
			t.Errorf("TotalTokens() = %d, want 60", resp.TotalTokens())
		}
	})

	t.Run("rejects an invalid language before the request", func(t *testing.T) {
		client := New("https://unused.test", "key")
		_, err := client.Chat(context.Background(), &ChatRequest{
			Messages: []Message{UserMessage("hi")},
			Language: Language("fr"),
		})
		if err == nil {
			t.Fatal("Chat with invalid language succeeded, want error")
		}
	})

	t.Run("maps 401 to ErrUnauthorized", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write(loadFixture(t, "error_401.json"))
		}))
		defer srv.Close()

		client := New(srv.URL, "wrong")
		_, err := client.Chat(context.Background(), &ChatRequest{
			Messages: []Message{UserMessage("hi")},
			Language: English,
		})
		if err == nil {
			t.Fatal("Chat succeeded, want error")
		}
		if !errors.Is(err, ErrUnauthorized) {
			t.Errorf("errors.Is(err, ErrUnauthorized) = false; err = %v", err)
		}

		var apiErr *APIError
		if !errors.As(err, &apiErr) {
			t.Fatalf("errors.As(*APIError) = false; err = %v", err)
		}
		if apiErr.StatusCode != 401 {
			t.Errorf("StatusCode = %d, want 401", apiErr.StatusCode)
		}
		if apiErr.Detail != "Invalid or missing API key" {
			t.Errorf("Detail = %q", apiErr.Detail)
		}
	})
}

func TestChatStream(t *testing.T) {
	t.Run("yields deltas and stops at [DONE]", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if got := r.Header.Get("Accept"); got != "text/event-stream" {
				t.Errorf("Accept = %q", got)
			}
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = w.Write(loadFixture(t, "chat_stream.txt"))
		}))
		defer srv.Close()

		client := New(srv.URL, "test_key")
		var deltas []string
		err := client.ChatStream(context.Background(), &ChatRequest{
			Messages: []Message{UserMessage("Sannu!")},
			Language: Hausa,
		}, func(delta string) error {
			deltas = append(deltas, delta)
			return nil
		})
		if err != nil {
			t.Fatalf("ChatStream: %v", err)
		}

		want := []string{"Sannu", " da", " zuwa", "!"}
		if len(deltas) != len(want) {
			t.Fatalf("deltas = %q, want %q", deltas, want)
		}
		for i := range want {
			if deltas[i] != want[i] {
				t.Errorf("deltas[%d] = %q, want %q", i, deltas[i], want[i])
			}
		}
		if joined := strings.Join(deltas, ""); joined != "Sannu da zuwa!" {
			t.Errorf("joined = %q", joined)
		}
	})

	t.Run("aborts when onChunk returns an error", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = w.Write(loadFixture(t, "chat_stream.txt"))
		}))
		defer srv.Close()

		sentinel := errors.New("stop here")
		client := New(srv.URL, "test_key")
		count := 0
		err := client.ChatStream(context.Background(), &ChatRequest{
			Messages: []Message{UserMessage("Sannu!")},
			Language: Hausa,
		}, func(delta string) error {
			count++
			return sentinel
		})
		if !errors.Is(err, sentinel) {
			t.Errorf("err = %v, want sentinel", err)
		}
		if count != 1 {
			t.Errorf("onChunk called %d times, want 1", count)
		}
	})
}

func TestTranscribe(t *testing.T) {
	t.Run("posts multipart with the language field", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != "/v1/audio/transcriptions" {
				t.Errorf("path = %q", r.URL.Path)
			}
			if ct := r.Header.Get("Content-Type"); !strings.HasPrefix(ct, "multipart/form-data") {
				t.Errorf("Content-Type = %q", ct)
			}
			if err := r.ParseMultipartForm(1 << 20); err != nil {
				t.Fatalf("ParseMultipartForm: %v", err)
			}
			if got := r.FormValue("language"); got != "ha" {
				t.Errorf("language field = %q, want ha", got)
			}
			file, header, err := r.FormFile("file")
			if err != nil {
				t.Fatalf("FormFile: %v", err)
			}
			defer file.Close()
			if header.Filename != "recording.m4a" {
				t.Errorf("filename = %q", header.Filename)
			}
			if got := header.Header.Get("Content-Type"); got != "audio/m4a" {
				t.Errorf("part Content-Type = %q, want audio/m4a", got)
			}
			contents, _ := io.ReadAll(file)
			if len(contents) != 4 {
				t.Errorf("audio len = %d, want 4", len(contents))
			}

			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write(loadFixture(t, "transcription_response.json"))
		}))
		defer srv.Close()

		client := New(srv.URL, "test_key")
		result, err := client.Transcribe(context.Background(), &TranscribeRequest{
			Audio:    []byte{0, 1, 2, 3},
			Language: Hausa,
			Filename: "recording.m4a",
		})
		if err != nil {
			t.Fatalf("Transcribe: %v", err)
		}
		if !strings.Contains(result.Text, "noma masara") {
			t.Errorf("Text = %q", result.Text)
		}
		if result.Language != Hausa {
			t.Errorf("Language = %v, want ha", result.Language)
		}
		if result.DurationSeconds != 4.82 {
			t.Errorf("DurationSeconds = %v, want 4.82", result.DurationSeconds)
		}
	})

	t.Run("rejects empty audio", func(t *testing.T) {
		client := New("https://unused.test", "key")
		_, err := client.Transcribe(context.Background(), &TranscribeRequest{
			Audio:    nil,
			Language: Hausa,
		})
		if err == nil {
			t.Fatal("Transcribe with empty audio succeeded, want error")
		}
	})
}

func TestVoiceChat(t *testing.T) {
	t.Run("transcribes then chats with history", func(t *testing.T) {
		var chatBody map[string]any

		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			switch r.URL.Path {
			case "/v1/audio/transcriptions":
				_, _ = w.Write(loadFixture(t, "transcription_response.json"))
			case "/v1/chat/completions":
				body, _ := io.ReadAll(r.Body)
				_ = json.Unmarshal(body, &chatBody)
				_, _ = w.Write(loadFixture(t, "chat_response.json"))
			default:
				t.Errorf("unexpected path %q", r.URL.Path)
			}
		}))
		defer srv.Close()

		client := New(srv.URL, "test_key")
		result, err := client.VoiceChat(context.Background(), &VoiceChatRequest{
			Audio:    []byte{0, 1, 2, 3},
			Language: Hausa,
			History:  []Message{UserMessage("earlier"), AssistantMessage("reply")},
		})
		if err != nil {
			t.Fatalf("VoiceChat: %v", err)
		}

		if !strings.Contains(result.Transcript.Text, "noma masara") {
			t.Errorf("Transcript.Text = %q", result.Transcript.Text)
		}
		if !strings.Contains(result.Reply, "Sannu da zuwa") {
			t.Errorf("Reply = %q", result.Reply)
		}

		msgs, ok := chatBody["messages"].([]any)
		if !ok {
			t.Fatalf("messages missing from chat body: %v", chatBody)
		}
		if len(msgs) != 3 {
			t.Fatalf("len(messages) = %d, want 3 (2 history + 1 transcript)", len(msgs))
		}
		last := msgs[2].(map[string]any)
		if last["content"] != result.Transcript.Text {
			t.Errorf("last message = %q, want the transcript", last["content"])
		}
		if last["role"] != "user" {
			t.Errorf("last message role = %q, want user", last["role"])
		}
	})
}

func TestHealth(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/health" {
			t.Errorf("path = %q", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(loadFixture(t, "health_response.json"))
	}))
	defer srv.Close()

	client := New(srv.URL, "test_key")
	health, err := client.Health(context.Background())
	if err != nil {
		t.Fatalf("Health: %v", err)
	}
	if health.Status != "ok" {
		t.Errorf("Status = %q", health.Status)
	}
	if health.Models.LLM != "NCAIR1/N-ATLaS" {
		t.Errorf("Models.LLM = %q", health.Models.LLM)
	}
	if len(health.Models.ASR) != 4 {
		t.Errorf("len(Models.ASR) = %d, want 4", len(health.Models.ASR))
	}
}

func TestNewTrimsTrailingSlash(t *testing.T) {
	client := New("https://gateway.test/", "key")
	if got := client.url("/health"); got != "https://gateway.test/health" {
		t.Errorf("url = %q, want https://gateway.test/health", got)
	}
}
