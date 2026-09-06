// axum + tokio multi-thread runtime: the idiomatic minimal Rust HTTP API.
// Contract: GET / -> 200, Content-Type: text/plain, Content-Length: 13, body "hello, world\n".
use axum::{routing::get, Router};

async fn hello() -> ([(&'static str, &'static str); 2], &'static str) {
    ([("content-type", "text/plain"), ("content-length", "13")], "hello, world\n")
}

#[tokio::main]
async fn main() {
    let port = std::env::args().nth(1).expect("usage: axum-hello PORT");
    let app = Router::new().route("/", get(hello));
    let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{port}")).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
