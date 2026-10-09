package natlas

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"
)

// TranscribeRequest describes a speech-to-text request.
type TranscribeRequest struct {
	// Audio is the raw audio bytes. Any format ffmpeg can read works —
	// ogg/opus, m4a, mp3, wav, webm. The gateway converts to 16 kHz mono WAV
	// and chunks anything over 28 seconds.
	Audio []byte

	// Language selects which ASR model handles the audio.
	Language Language

	// Filename is sent in the multipart part. The extension tells the gateway
	// which container to expect. Defaults to "audio.ogg".
	Filename string
}

// Transcribe converts audio to text using the ASR model for the language.
func (c *Client) Transcribe(ctx context.Context, req *TranscribeRequest) (*Transcription, error) {
	if !req.Language.Valid() {
		return nil, fmt.Errorf("natlas: invalid language %q", req.Language)
	}
	if len(req.Audio) == 0 {
		return nil, fmt.Errorf("natlas: audio is empty")
	}

	filename := req.Filename
	if filename == "" {
		filename = "audio.ogg"
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)

	if err := writer.WriteField("language", string(req.Language)); err != nil {
		return nil, fmt.Errorf("natlas: write language field: %w", err)
	}

	part, err := newAudioPart(writer, filename)
	if err != nil {
		return nil, fmt.Errorf("natlas: create audio part: %w", err)
	}
	if _, err := part.Write(req.Audio); err != nil {
		return nil, fmt.Errorf("natlas: write audio: %w", err)
	}
	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("natlas: close multipart writer: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(
		ctx, http.MethodPost, c.url("/v1/audio/transcriptions"), &body)
	if err != nil {
		return nil, fmt.Errorf("natlas: build request: %w", err)
	}
	c.setAuth(httpReq)
	httpReq.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("natlas: transcribe request: %w", err)
	}
	defer resp.Body.Close()

	if err := checkResponse(resp); err != nil {
		return nil, err
	}

	var out Transcription
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("natlas: decode response: %w", err)
	}
	return &out, nil
}

// newAudioPart creates a multipart file part with the right Content-Type
// for the filename's extension.
func newAudioPart(w *multipart.Writer, filename string) (io.Writer, error) {
	h := make(map[string][]string)
	h["Content-Disposition"] = []string{
		fmt.Sprintf(`form-data; name="file"; filename=%q`, filename),
	}
	h["Content-Type"] = []string{mimeForExt(filepath.Ext(filename))}
	return w.CreatePart(h)
}

func mimeForExt(ext string) string {
	switch strings.ToLower(strings.TrimPrefix(ext, ".")) {
	case "ogg", "opus":
		return "audio/ogg"
	case "mp3":
		return "audio/mpeg"
	case "m4a", "mp4", "aac":
		return "audio/m4a"
	case "wav":
		return "audio/wav"
	case "webm":
		return "audio/webm"
	case "flac":
		return "audio/flac"
	default:
		return "application/octet-stream"
	}
}
