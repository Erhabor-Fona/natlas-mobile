mod common;

use common::load_fixture;
use futures_util::StreamExt;
use natlas::{ChatMessage, ChatRequest, Language, NAtlasClient};
use std::str::FromStr;
use wiremock::matchers::{header, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

fn client(server: &MockServer) -> NAtlasClient {
    NAtlasClient::new(server.uri(), "test_key")
}

// ── Language ────────────────────────────────────────────────────────────────

#[test]
fn language_codes_match_the_gateway_contract() {
    assert_eq!(Language::Hausa.code(), "ha");
    assert_eq!(Language::Igbo.code(), "ig");
    assert_eq!(Language::Yoruba.code(), "yo");
    assert_eq!(Language::English.code(), "en");
}

#[test]
fn language_from_str_round_trips() {
    for lang in Language::ALL {
        assert_eq!(Language::from_str(lang.code()).unwrap(), lang);
    }
}

#[test]
fn language_from_str_rejects_unknown_codes() {
    assert!(Language::from_str("fr").is_err());
}

#[test]
fn language_display_names() {
    assert_eq!(Language::Yoruba.display_name(), "Yorùbá");
    assert_eq!(Language::English.display_name(), "Nigerian English");
}

// ── Chat ────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn chat_sends_the_documented_request_body() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .and(header("authorization", "Bearer test_key"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("chat_response.json"), "application/json"),
        )
        .mount(&server)
        .await;

    let response = client(&server)
        .chat(
            vec![ChatMessage::user("Sannu! Yaya aiki?")],
            Language::Hausa,
        )
        .await
        .expect("chat");

    assert!(response.content().contains("Sannu da zuwa"));
    assert_eq!(response.usage.prompt_tokens, 42);
    assert_eq!(response.usage.completion_tokens, 18);
    assert_eq!(response.usage.total_tokens(), 60);

    // Verify the body the client actually sent.
    let requests = server.received_requests().await.unwrap();
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["language"], "ha");
    assert_eq!(body["stream"], false);
    assert_eq!(body["temperature"], 0.7);
    assert_eq!(body["max_tokens"], 512);
    assert_eq!(body["messages"][0]["role"], "user");
    assert_eq!(body["messages"][0]["content"], "Sannu! Yaya aiki?");
}

#[tokio::test]
async fn chat_request_builder_overrides_sampling() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("chat_response.json"), "application/json"),
        )
        .mount(&server)
        .await;

    let request = ChatRequest::new(vec![ChatMessage::user("hi")], Language::Igbo)
        .temperature(0.2)
        .max_tokens(128);

    client(&server).chat_with(request).await.expect("chat_with");

    let requests = server.received_requests().await.unwrap();
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["temperature"], 0.2);
    assert_eq!(body["max_tokens"], 128);
    assert_eq!(body["language"], "ig");
}

#[tokio::test]
async fn chat_surfaces_401_as_unauthorized() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .respond_with(
            ResponseTemplate::new(401)
                .set_body_raw(load_fixture("error_401.json"), "application/json"),
        )
        .mount(&server)
        .await;

    let err = client(&server)
        .chat(vec![ChatMessage::user("hi")], Language::English)
        .await
        .expect_err("expected 401");

    assert_eq!(err.status(), Some(401));
    assert!(err.is_unauthorized());
    // FastAPI's {"detail": ...} envelope is unwrapped.
    assert!(
        err.to_string().contains("Invalid or missing API key"),
        "error was: {err}"
    );
}

// ── Streaming ───────────────────────────────────────────────────────────────

#[tokio::test]
async fn chat_stream_yields_deltas_and_stops_at_done() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .and(header("accept", "text/event-stream"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("chat_stream.txt"), "text/event-stream"),
        )
        .mount(&server)
        .await;

    let mut stream = client(&server)
        .chat_stream(vec![ChatMessage::user("Sannu!")], Language::Hausa)
        .await
        .expect("chat_stream");

    let mut deltas = Vec::new();
    while let Some(chunk) = stream.next().await {
        deltas.push(chunk.expect("chunk").delta().to_string());
    }

    assert_eq!(deltas, vec!["Sannu", " da", " zuwa", "!"]);
    assert_eq!(deltas.concat(), "Sannu da zuwa!");
}

#[tokio::test]
async fn chat_stream_sets_stream_true() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("chat_stream.txt"), "text/event-stream"),
        )
        .mount(&server)
        .await;

    let mut stream = client(&server)
        .chat_stream(vec![ChatMessage::user("hi")], Language::Hausa)
        .await
        .expect("chat_stream");
    while stream.next().await.is_some() {}

    let requests = server.received_requests().await.unwrap();
    let body: serde_json::Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["stream"], true);
}

// ── Transcription ───────────────────────────────────────────────────────────

#[tokio::test]
async fn transcribe_posts_multipart_with_language() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/audio/transcriptions"))
        .and(header("authorization", "Bearer test_key"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            load_fixture("transcription_response.json"),
            "application/json",
        ))
        .mount(&server)
        .await;

    let result = client(&server)
        .transcribe(vec![0, 1, 2, 3], Language::Hausa, "recording.m4a")
        .await
        .expect("transcribe");

    assert!(result.text.contains("noma masara"));
    assert_eq!(result.language, Language::Hausa);
    assert!((result.duration_seconds - 4.82).abs() < 1e-6);

    let requests = server.received_requests().await.unwrap();
    let body = String::from_utf8_lossy(&requests[0].body);
    assert!(body.contains("name=\"language\""));
    assert!(body.contains("ha"));
    assert!(body.contains("recording.m4a"));
    assert!(body.contains("audio/m4a"));

    let content_type = requests[0]
        .headers
        .get("content-type")
        .unwrap()
        .to_str()
        .unwrap();
    assert!(content_type.starts_with("multipart/form-data"));
}

#[tokio::test]
async fn transcribe_rejects_empty_audio() {
    let server = MockServer::start().await;

    let err = client(&server)
        .transcribe(vec![], Language::Hausa, "empty.ogg")
        .await
        .expect_err("expected empty-audio error");

    assert!(err.to_string().contains("empty"), "error was: {err}");
    // No request should have been sent.
    assert!(server.received_requests().await.unwrap().is_empty());
}

// ── Voice chat ──────────────────────────────────────────────────────────────

#[tokio::test]
async fn voice_chat_transcribes_then_chats_with_history() {
    let server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v1/audio/transcriptions"))
        .respond_with(ResponseTemplate::new(200).set_body_raw(
            load_fixture("transcription_response.json"),
            "application/json",
        ))
        .mount(&server)
        .await;

    Mock::given(method("POST"))
        .and(path("/v1/chat/completions"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("chat_response.json"), "application/json"),
        )
        .mount(&server)
        .await;

    let history = vec![
        ChatMessage::user("earlier"),
        ChatMessage::assistant("reply"),
    ];

    let result = client(&server)
        .voice_chat(vec![0, 1, 2, 3], Language::Hausa, "a.ogg", history)
        .await
        .expect("voice_chat");

    assert!(result.transcript.text.contains("noma masara"));
    assert!(result.reply.contains("Sannu da zuwa"));

    // The chat call should carry history plus the transcript as the last turn.
    let requests = server.received_requests().await.unwrap();
    let chat_request = requests
        .iter()
        .find(|r| r.url.path() == "/v1/chat/completions")
        .expect("chat request");
    let body: serde_json::Value = serde_json::from_slice(&chat_request.body).unwrap();
    let messages = body["messages"].as_array().unwrap();

    assert_eq!(messages.len(), 3);
    assert_eq!(messages[2]["role"], "user");
    assert_eq!(messages[2]["content"], result.transcript.text);
}

// ── Health ──────────────────────────────────────────────────────────────────

#[tokio::test]
async fn health_parses_the_shared_fixture() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/health"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("health_response.json"), "application/json"),
        )
        .mount(&server)
        .await;

    let health = client(&server).health().await.expect("health");

    assert_eq!(health.status, "ok");
    assert_eq!(health.models.llm, "NCAIR1/N-ATLaS");
    assert_eq!(health.models.asr.len(), 4);
}

// ── Builder ─────────────────────────────────────────────────────────────────

#[tokio::test]
async fn builder_trims_trailing_slash_from_base_url() {
    let server = MockServer::start().await;

    Mock::given(method("GET"))
        .and(path("/health"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_raw(load_fixture("health_response.json"), "application/json"),
        )
        .mount(&server)
        .await;

    // A trailing slash would otherwise produce "//health".
    let client = NAtlasClient::builder(format!("{}/", server.uri()), "test_key")
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .expect("build");

    assert!(client.health().await.is_ok());
}
