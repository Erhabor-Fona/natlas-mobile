package natlas

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// Chat sends messages and returns the complete reply.
func (c *Client) Chat(ctx context.Context, req *ChatRequest) (*ChatResponse, error) {
	if !req.Language.Valid() {
		return nil, fmt.Errorf("natlas: invalid language %q", req.Language)
	}
	req.Stream = false

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("natlas: marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(
		ctx, http.MethodPost, c.url("/v1/chat/completions"), bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("natlas: build request: %w", err)
	}
	c.setAuth(httpReq)
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("natlas: chat request: %w", err)
	}
	defer resp.Body.Close()

	if err := checkResponse(resp); err != nil {
		return nil, err
	}

	var out ChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("natlas: decode response: %w", err)
	}
	return &out, nil
}

// ChatStream streams the reply, calling onChunk for each delta as it arrives.
//
// onChunk receives delta text only, not the accumulated reply. Returning a
// non-nil error from onChunk aborts the stream and ChatStream returns that
// error. The stream also stops when ctx is cancelled.
func (c *Client) ChatStream(
	ctx context.Context,
	req *ChatRequest,
	onChunk func(delta string) error,
) error {
	if !req.Language.Valid() {
		return fmt.Errorf("natlas: invalid language %q", req.Language)
	}
	req.Stream = true

	body, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("natlas: marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(
		ctx, http.MethodPost, c.url("/v1/chat/completions"), bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("natlas: build request: %w", err)
	}
	c.setAuth(httpReq)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return fmt.Errorf("natlas: stream request: %w", err)
	}
	defer resp.Body.Close()

	if err := checkResponse(resp); err != nil {
		return err
	}

	scanner := bufio.NewScanner(resp.Body)
	// SSE lines can exceed bufio's 64 KiB default on long single-token bursts.
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		line := scanner.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data: "))
		if data == "[DONE]" {
			return nil
		}

		var chunk StreamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue // malformed SSE line — skip
		}
		if delta := chunk.Delta(); delta != "" {
			if err := onChunk(delta); err != nil {
				return err
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("natlas: read stream: %w", err)
	}
	return nil
}

// Health checks that the gateway is up and its models are loaded.
func (c *Client) Health(ctx context.Context) (*Health, error) {
	httpReq, err := http.NewRequestWithContext(
		ctx, http.MethodGet, c.url("/health"), nil)
	if err != nil {
		return nil, fmt.Errorf("natlas: build request: %w", err)
	}
	httpReq.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("natlas: health request: %w", err)
	}
	defer resp.Body.Close()

	if err := checkResponse(resp); err != nil {
		return nil, err
	}

	var out Health
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("natlas: decode response: %w", err)
	}
	return &out, nil
}
