use thiserror::Error;

/// Errors returned by the N-ATLaS client.
#[derive(Debug, Error)]
pub enum Error {
    /// The gateway returned a non-2xx status.
    #[error("natlas: {} (HTTP {status}): {detail}", status_message(*status))]
    Api {
        /// HTTP status code.
        status: u16,
        /// Error detail from the gateway body.
        detail: String,
    },

    /// The request could not be sent, or the connection failed.
    #[error("natlas: request failed: {0}")]
    Http(#[from] reqwest::Error),

    /// A response body could not be parsed.
    #[error("natlas: decode response: {0}")]
    Decode(#[from] serde_json::Error),

    /// A language code the gateway does not support.
    #[error("natlas: unknown language code {0:?}")]
    UnknownLanguage(String),

    /// Audio was empty or otherwise unusable.
    #[error("natlas: invalid audio: {0}")]
    InvalidAudio(String),
}

impl Error {
    /// The HTTP status, if this was an API error.
    pub fn status(&self) -> Option<u16> {
        match self {
            Error::Api { status, .. } => Some(*status),
            _ => None,
        }
    }

    /// True if the gateway rejected the API key.
    pub fn is_unauthorized(&self) -> bool {
        self.status() == Some(401)
    }

    /// True if the gateway is throttling.
    pub fn is_rate_limited(&self) -> bool {
        self.status() == Some(429)
    }
}

fn status_message(code: u16) -> &'static str {
    match code {
        400 => "bad request",
        401 => "unauthorized — check your API key",
        422 => "unprocessable content",
        429 => "rate limited",
        500 => "gateway internal error",
        _ => "request failed",
    }
}

/// Result alias for this crate.
pub type Result<T> = std::result::Result<T, Error>;
