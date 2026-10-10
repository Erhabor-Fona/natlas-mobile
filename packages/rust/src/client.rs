use std::time::Duration;

use reqwest::{Client as HttpClient, Response};

use crate::error::{Error, Result};

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

/// Client for a N-ATLaS gateway.
///
/// Cloning is cheap — the underlying connection pool is shared.
#[derive(Debug, Clone)]
pub struct NAtlasClient {
    pub(crate) base_url: String,
    pub(crate) api_key: String,
    pub(crate) http: HttpClient,
}

impl NAtlasClient {
    /// Create a client pointed at a gateway base URL.
    ///
    /// # Panics
    /// Panics if the default TLS backend cannot be initialised. Use
    /// [`NAtlasClient::builder`] to handle that case without panicking.
    pub fn new(base_url: impl Into<String>, api_key: impl Into<String>) -> Self {
        Self::builder(base_url, api_key)
            .build()
            .expect("failed to build default HTTP client")
    }

    /// Start configuring a client.
    pub fn builder(base_url: impl Into<String>, api_key: impl Into<String>) -> NAtlasClientBuilder {
        NAtlasClientBuilder {
            base_url: base_url.into(),
            api_key: api_key.into(),
            timeout: DEFAULT_TIMEOUT,
            http: None,
        }
    }

    pub(crate) fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    pub(crate) fn bearer(&self) -> String {
        format!("Bearer {}", self.api_key)
    }

    /// Turn a non-2xx response into [`Error::Api`], unwrapping FastAPI's
    /// `{"detail": ...}` envelope when present.
    pub(crate) async fn check(response: Response) -> Result<Response> {
        let status = response.status();
        if status.is_success() {
            return Ok(response);
        }

        let body = response.text().await.unwrap_or_default();
        let detail = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|v| {
                v.get("detail").map(|d| match d {
                    serde_json::Value::String(s) => s.clone(),
                    other => other.to_string(),
                })
            })
            .unwrap_or_else(|| body.trim().to_string());

        Err(Error::Api {
            status: status.as_u16(),
            detail,
        })
    }

    /// Check that the gateway is up and its models are loaded.
    pub async fn health(&self) -> Result<crate::models::Health> {
        let response = self
            .http
            .get(self.url("/health"))
            .header("Accept", "application/json")
            .send()
            .await?;

        let response = Self::check(response).await?;
        Ok(response.json().await?)
    }
}

/// Builder for [`NAtlasClient`].
#[derive(Debug)]
pub struct NAtlasClientBuilder {
    base_url: String,
    api_key: String,
    timeout: Duration,
    http: Option<HttpClient>,
}

impl NAtlasClientBuilder {
    /// Request timeout. Raise this for long generations.
    pub fn timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Supply a pre-configured [`reqwest::Client`] — for custom transports,
    /// proxies, tracing middleware, or a shared pool. Overrides `timeout`.
    pub fn http_client(mut self, http: HttpClient) -> Self {
        self.http = Some(http);
        self
    }

    /// Build the client.
    pub fn build(self) -> Result<NAtlasClient> {
        let http = match self.http {
            Some(http) => http,
            None => HttpClient::builder().timeout(self.timeout).build()?,
        };

        Ok(NAtlasClient {
            base_url: self.base_url.trim_end_matches('/').to_string(),
            api_key: self.api_key,
            http,
        })
    }
}
