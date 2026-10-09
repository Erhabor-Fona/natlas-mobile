// Package natlas is a Go client for N-ATLaS, Nigeria's sovereign
// multilingual LLM — Hausa, Igbo, Yorùbá, and Nigerian English.
//
//	client := natlas.New(os.Getenv("NATLAS_BASE_URL"), os.Getenv("NATLAS_API_KEY"))
//
//	resp, err := client.Chat(ctx, &natlas.ChatRequest{
//	    Messages: []natlas.Message{natlas.UserMessage("Sannu!")},
//	    Language: natlas.Hausa,
//	})
package natlas

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
)

const defaultTimeout = 60 * time.Second

// Client talks to a N-ATLaS gateway.
type Client struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
}

// Option configures a Client.
type Option func(*Client)

// WithHTTPClient supplies a custom *http.Client — useful for tests,
// custom transports, or a shared connection pool.
func WithHTTPClient(hc *http.Client) Option {
	return func(c *Client) { c.httpClient = hc }
}

// WithTimeout sets the request timeout on the default HTTP client.
// Ignored if WithHTTPClient is also supplied.
func WithTimeout(d time.Duration) Option {
	return func(c *Client) {
		if c.httpClient != nil {
			c.httpClient.Timeout = d
		}
	}
}

// New creates a Client pointed at a gateway base URL.
func New(baseURL, apiKey string, opts ...Option) *Client {
	c := &Client{
		baseURL:    strings.TrimRight(baseURL, "/"),
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: defaultTimeout},
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

func (c *Client) url(path string) string {
	return c.baseURL + path
}

func (c *Client) setAuth(req *http.Request) {
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Accept", "application/json")
}

// checkResponse converts a non-2xx response into an *APIError.
// On success it returns nil and leaves the body unread.
func checkResponse(resp *http.Response) error {
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	body, _ := io.ReadAll(resp.Body)
	detail := strings.TrimSpace(string(body))

	// FastAPI wraps errors as {"detail": "..."} — unwrap for a cleaner message.
	var wrapper struct {
		Detail json.RawMessage `json:"detail"`
	}
	if err := json.Unmarshal(body, &wrapper); err == nil && len(wrapper.Detail) > 0 {
		var s string
		if err := json.Unmarshal(wrapper.Detail, &s); err == nil {
			detail = s
		} else {
			detail = string(wrapper.Detail)
		}
	}

	return &APIError{StatusCode: resp.StatusCode, Detail: detail}
}
