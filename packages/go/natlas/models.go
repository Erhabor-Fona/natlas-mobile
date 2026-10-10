package natlas

import "fmt"

// Language is a language supported by N-ATLaS.
type Language string

const (
	Hausa   Language = "ha"
	Igbo    Language = "ig"
	Yoruba  Language = "yo"
	English Language = "en"
)

// DisplayName returns the human-readable name of the language.
func (l Language) DisplayName() string {
	switch l {
	case Hausa:
		return "Hausa"
	case Igbo:
		return "Igbo"
	case Yoruba:
		return "Yorùbá"
	case English:
		return "Nigerian English"
	default:
		return string(l)
	}
}

// Valid reports whether the language is one the gateway accepts.
func (l Language) Valid() bool {
	switch l {
	case Hausa, Igbo, Yoruba, English:
		return true
	}
	return false
}

// ParseLanguage converts a language code into a Language.
func ParseLanguage(code string) (Language, error) {
	l := Language(code)
	if !l.Valid() {
		return "", fmt.Errorf("natlas: unknown language code %q", code)
	}
	return l, nil
}

// Message is a single message in a conversation.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// UserMessage builds a message with the "user" role.
func UserMessage(content string) Message {
	return Message{Role: "user", Content: content}
}

// AssistantMessage builds a message with the "assistant" role.
func AssistantMessage(content string) Message {
	return Message{Role: "assistant", Content: content}
}

// SystemMessage builds a message with the "system" role.
func SystemMessage(content string) Message {
	return Message{Role: "system", Content: content}
}

// ChatRequest is the body of a chat completion request.
type ChatRequest struct {
	Messages    []Message `json:"messages"`
	Language    Language  `json:"language"`
	Temperature float64   `json:"temperature,omitempty"`
	MaxTokens   int       `json:"max_tokens,omitempty"`
	Stream      bool      `json:"stream"`
}

// ChatResponse is a non-streaming chat completion response.
type ChatResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Choices []struct {
		Index   int     `json:"index"`
		Message Message `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
}

// Content returns the assistant's reply text, or "" if there are no choices.
func (r *ChatResponse) Content() string {
	if len(r.Choices) == 0 {
		return ""
	}
	return r.Choices[0].Message.Content
}

// TotalTokens returns prompt plus completion tokens.
func (r *ChatResponse) TotalTokens() int {
	return r.Usage.PromptTokens + r.Usage.CompletionTokens
}

// StreamChunk is one delta from a streamed completion.
type StreamChunk struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Choices []struct {
		Index int `json:"index"`
		Delta struct {
			Content string `json:"content"`
		} `json:"delta"`
	} `json:"choices"`
}

// Delta returns the new text in this chunk.
func (c *StreamChunk) Delta() string {
	if len(c.Choices) == 0 {
		return ""
	}
	return c.Choices[0].Delta.Content
}

// Transcription is the result of a speech-to-text request.
type Transcription struct {
	Text            string   `json:"text"`
	Language        Language `json:"language"`
	DurationSeconds float64  `json:"duration_seconds"`
}

// VoiceChatResult pairs a transcription with the model's reply to it.
type VoiceChatResult struct {
	Transcript Transcription
	Reply      string
}

// Health is the gateway liveness response.
type Health struct {
	Status string `json:"status"`
	Models struct {
		LLM string   `json:"llm"`
		ASR []string `json:"asr"`
	} `json:"models"`
	Timestamp int64 `json:"timestamp"`
}
