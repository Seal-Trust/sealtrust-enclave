// Copyright (c), Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

//! Local development server for TruthMarket Nautilus enclave
//!
//! This is a mock server for local testing WITHOUT AWS Nitro Enclave.
//! For production, deploy using the full Nautilus infrastructure.

use axum::{routing::{get, post}, Router};
use fastcrypto::ed25519::Ed25519KeyPair;
use fastcrypto::traits::KeyPair;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tower_http::cors::{CorsLayer, Any};
use truthmarket_nautilus::{process_data, AppState};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    // Generate ephemeral keypair for signing (in real enclave, this comes from NSM)
    let eph_kp = Ed25519KeyPair::generate(&mut rand::thread_rng());

    println!("🔐 Ephemeral public key: {:?}", eph_kp.public());
    println!("⚠️  WARNING: This is a DEV server. Use real Nautilus enclave for production!");

    let state = Arc::new(AppState {
        eph_kp,
        api_key: "local-dev-key".to_string(),
    });

    // Configure CORS to allow requests from frontend
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/process_data", post(process_data))
        .route("/health", get(|| async { "OK" }))
        .layer(cors)
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 3000));
    let listener = TcpListener::bind(addr).await?;

    println!("🚀 TruthMarket Nautilus server listening on http://{}", addr);
    println!("📡 Endpoints:");
    println!("   POST /process_data - Verify dataset and return signed hash");
    println!("   GET  /health       - Health check");

    axum::serve(listener, app).await?;

    Ok(())
}
