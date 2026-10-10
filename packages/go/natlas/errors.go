package natlas

import (
	"errors"
	"fmt"
)

// APIError is returned when the gateway responds with a non-2xx status.
type APIError struct {
	StatusCode int
	Detail     string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("natlas: %s (HTTP %d): %s", statusMessage(e.StatusCode), e.StatusCode, e.Detail)
}

func statusMessage(code int) string {
	switch code {
	case 400:
		return "bad request"
	case 401:
		return "unauthorized — check your API key"
	case 422:
		return "unprocessable content"
	case 429:
		return "rate limited"
	case 500:
		return "gateway internal error"
	default:
		return "request failed"
	}
}

// Sentinel errors callers can match with errors.Is.
var (
	// ErrUnauthorized indicates a bad or missing API key.
	ErrUnauthorized = errors.New("natlas: unauthorized")
	// ErrRateLimited indicates the gateway is throttling.
	ErrRateLimited = errors.New("natlas: rate limited")
	// ErrBadRequest indicates the gateway rejected the request body.
	ErrBadRequest = errors.New("natlas: bad request")
)

// Is lets errors.Is match an APIError against the sentinels above.
func (e *APIError) Is(target error) bool {
	switch e.StatusCode {
	case 401:
		return target == ErrUnauthorized
	case 429:
		return target == ErrRateLimited
	case 400, 422:
		return target == ErrBadRequest
	}
	return false
}
