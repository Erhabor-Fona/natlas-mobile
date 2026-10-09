package natlas

import "context"

// VoiceChatRequest describes a one-call voice → text → reply round trip.
type VoiceChatRequest struct {
	// Audio is the raw recording. See TranscribeRequest.Audio for formats.
	Audio []byte

	// Language selects both the ASR model and the reply language.
	Language Language

	// Filename is sent in the multipart part. Defaults to "audio.ogg".
	Filename string

	// History is prepended to the transcribed message, so the model sees the
	// conversation so far.
	History []Message

	// Temperature and MaxTokens are passed through to the chat call.
	Temperature float64
	MaxTokens   int
}

// VoiceChat transcribes the audio, sends the transcript to N-ATLaS, and
// returns both the transcription and the reply.
//
// This is two HTTP round trips. If you need the transcript before the reply
// (to render it immediately), call Transcribe and Chat separately.
func (c *Client) VoiceChat(ctx context.Context, req *VoiceChatRequest) (*VoiceChatResult, error) {
	transcription, err := c.Transcribe(ctx, &TranscribeRequest{
		Audio:    req.Audio,
		Language: req.Language,
		Filename: req.Filename,
	})
	if err != nil {
		return nil, err
	}

	messages := make([]Message, 0, len(req.History)+1)
	messages = append(messages, req.History...)
	messages = append(messages, UserMessage(transcription.Text))

	chatResp, err := c.Chat(ctx, &ChatRequest{
		Messages:    messages,
		Language:    req.Language,
		Temperature: req.Temperature,
		MaxTokens:   req.MaxTokens,
	})
	if err != nil {
		return nil, err
	}

	return &VoiceChatResult{
		Transcript: *transcription,
		Reply:      chatResp.Content(),
	}, nil
}
