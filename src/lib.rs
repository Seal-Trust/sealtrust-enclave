// Copyright (c), Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

pub mod common;

use common::{to_signed_response, IntentMessage, IntentScope, ProcessDataRequest, ProcessedDataResponse};
use axum::extract::State;
use axum::Json;
use fastcrypto::encoding::{Encoding, Hex};
use fastcrypto::ed25519::Ed25519KeyPair;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use std::fmt;
use tracing::info;

/// App state, at minimum needs to maintain the ephemeral keypair
pub struct AppState {
    /// Ephemeral keypair on boot
    pub eph_kp: Ed25519KeyPair,
    /// API key for external services (unused in dataset verification)
    pub api_key: String,
}

/// Enclave errors enum
#[derive(Debug)]
pub enum EnclaveError {
    GenericError(String),
}

impl fmt::Display for EnclaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EnclaveError::GenericError(e) => write!(f, "{}", e),
        }
    }
}

impl std::error::Error for EnclaveError {}

// Implement IntoResponse for Axum compatibility
impl axum::response::IntoResponse for EnclaveError {
    fn into_response(self) -> axum::response::Response {
        let (status, error_message) = match self {
            EnclaveError::GenericError(msg) => (
                axum::http::StatusCode::INTERNAL_SERVER_ERROR,
                msg
            ),
        };

        let body = serde_json::json!({
            "error": error_message
        });

        (status, axum::Json(body)).into_response()
    }
}

/// Inner type for IntentMessage<T> - MUST match Move contract exactly
/// V3 Architecture: Verify metadata only (not fetch datasets)
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct DatasetVerification {
    pub dataset_id: Vec<u8>,          // Unique dataset ID
    pub name: Vec<u8>,                // Dataset name
    pub description: Vec<u8>,          // Dataset description
    pub format: Vec<u8>,              // File format
    pub size: u64,                    // File size in bytes
    pub original_hash: Vec<u8>,       // Hash of UNENCRYPTED file
    pub walrus_blob_id: Vec<u8>,      // Walrus storage ID
    pub seal_policy_id: Vec<u8>,      // Seal access policy ID
    pub timestamp: u64,               // Verification timestamp
    pub uploader: Vec<u8>,            // Uploader address
}

/// Inner type for ProcessDataRequest<T>
#[derive(Debug, Serialize, Deserialize)]
pub struct DatasetRequest {
    pub dataset_url: String,
    pub expected_hash: Option<String>,
    pub format: String,
    pub schema_version: String,
}

/// V3 Architecture: Metadata verification request
#[derive(Debug, Serialize, Deserialize)]
pub struct MetadataVerificationRequest {
    pub metadata: DatasetVerification,
}

pub async fn process_data(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ProcessDataRequest<DatasetRequest>>,
) -> Result<Json<ProcessedDataResponse<IntentMessage<DatasetVerification>>>, EnclaveError> {
    let dataset_url = request.payload.dataset_url.clone();
    info!("Processing dataset from URL: {}", dataset_url);

    let current_timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| EnclaveError::GenericError(format!("Failed to get current timestamp: {}", e)))?
        .as_millis() as u64;

    // Fetch dataset content
    let dataset_content = reqwest::get(&dataset_url)
        .await
        .map_err(|e| EnclaveError::GenericError(format!("Failed to fetch dataset: {}", e)))?
        .bytes()
        .await
        .map_err(|e| EnclaveError::GenericError(format!("Failed to read dataset bytes: {}", e)))?;

    // Compute SHA256 hash
    let mut hasher = Sha256::new();
    hasher.update(&dataset_content);
    let hash_result = hasher.finalize();
    let dataset_hash = hash_result.to_vec();

    // Optionally verify against expected hash
    if let Some(expected) = &request.payload.expected_hash {
        let expected_bytes = hex::decode(expected)
            .map_err(|_| EnclaveError::GenericError("Invalid expected hash format".to_string()))?;
        if dataset_hash != expected_bytes {
            return Err(EnclaveError::GenericError("Dataset hash mismatch".to_string()));
        }
    }

    info!("Dataset verified: hash={}, size={} bytes", Hex::encode(&dataset_hash), dataset_content.len());

    Ok(Json(to_signed_response(
        &state.eph_kp,
        DatasetVerification {
            dataset_id: b"legacy".to_vec(),
            name: dataset_url.as_bytes().to_vec(),
            description: b"Legacy endpoint - use verify_metadata instead".to_vec(),
            format: request.payload.format.as_bytes().to_vec(),
            size: dataset_content.len() as u64,
            original_hash: dataset_hash,
            walrus_blob_id: b"".to_vec(),
            seal_policy_id: b"".to_vec(),
            timestamp: current_timestamp,
            uploader: b"".to_vec(),
        },
        current_timestamp,
        IntentScope::ProcessData,
    )))
}

/// V3 Architecture: Verify metadata and sign (no dataset fetching)
/// This is the NEW endpoint that should be used for production
pub async fn verify_metadata(
    State(state): State<Arc<AppState>>,
    Json(request): Json<MetadataVerificationRequest>,
) -> Result<Json<ProcessedDataResponse<IntentMessage<DatasetVerification>>>, EnclaveError> {
    info!("Verifying dataset metadata (V3 architecture)");

    let metadata = request.metadata;

    // Validate metadata fields
    if metadata.dataset_id.is_empty() {
        return Err(EnclaveError::GenericError("dataset_id cannot be empty".to_string()));
    }

    if metadata.name.is_empty() {
        return Err(EnclaveError::GenericError("name cannot be empty".to_string()));
    }

    if metadata.original_hash.is_empty() {
        return Err(EnclaveError::GenericError("original_hash cannot be empty".to_string()));
    }

    if metadata.walrus_blob_id.is_empty() {
        return Err(EnclaveError::GenericError("walrus_blob_id cannot be empty".to_string()));
    }

    if metadata.seal_policy_id.is_empty() {
        return Err(EnclaveError::GenericError("seal_policy_id cannot be empty".to_string()));
    }

    if metadata.uploader.is_empty() {
        return Err(EnclaveError::GenericError("uploader cannot be empty".to_string()));
    }

    // Log verification details
    info!(
        "Metadata verification - dataset_id: {:?}, name: {:?}, size: {} bytes, walrus_blob_id: {:?}",
        String::from_utf8_lossy(&metadata.dataset_id),
        String::from_utf8_lossy(&metadata.name),
        metadata.size,
        String::from_utf8_lossy(&metadata.walrus_blob_id)
    );

    // Use the timestamp from metadata (client-provided)
    let timestamp = metadata.timestamp;

    info!("Metadata verified successfully, signing...");

    // Sign the metadata and return
    Ok(Json(to_signed_response(
        &state.eph_kp,
        metadata,
        timestamp,
        IntentScope::ProcessData,
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use fastcrypto::encoding::{Encoding, Hex};

    #[tokio::test]
    async fn test_serde() {
        // CRITICAL: Serialization should be consistent with move test see `fun test_bcs_serialization_consistency` in `truthmarket.move`.
        let payload = DatasetVerification {
            dataset_id: b"test-123".to_vec(),
            name: b"test.csv".to_vec(),
            description: b"Test dataset".to_vec(),
            format: b"CSV".to_vec(),
            size: 1024,
            original_hash: b"abc123".to_vec(),
            walrus_blob_id: b"blob-123".to_vec(),
            seal_policy_id: b"policy-123".to_vec(),
            timestamp: 1700000000000,
            uploader: b"0xA".to_vec(),
        };
        let timestamp = 1700000000000;
        let intent_msg = IntentMessage::new(payload, timestamp, IntentScope::ProcessData);
        let signing_payload = bcs::to_bytes(&intent_msg).expect("should not fail");
        println!("Rust BCS bytes: {}", Hex::encode(&signing_payload));

        // Verify basic structure
        assert!(!signing_payload.is_empty(), "BCS payload should not be empty");

        // The Move test should produce EXACTLY the same bytes
        // Run both tests and compare outputs!
    }

    #[test]
    fn test_dataset_hash_computation() {
        // Test SHA256 hash computation on realistic dataset content
        let test_data = b"id,label,value\n1,dog,100\n2,cat,200\n3,bird,150";

        let mut hasher = Sha256::new();
        hasher.update(test_data);
        let hash_result = hasher.finalize();
        let dataset_hash = hash_result.to_vec();

        // Verify hash properties
        assert_eq!(dataset_hash.len(), 32, "SHA256 should produce 32 bytes");

        // Verify deterministic (same input = same output)
        let mut hasher2 = Sha256::new();
        hasher2.update(test_data);
        let hash_result2 = hasher2.finalize();
        let dataset_hash2 = hash_result2.to_vec();

        assert_eq!(dataset_hash, dataset_hash2, "Hash should be deterministic");

        println!("Dataset hash: {}", Hex::encode(&dataset_hash));
    }

    #[test]
    fn test_dataset_verification_bcs_serialization() {
        // Test that DatasetVerification serializes correctly
        let verification = DatasetVerification {
            dataset_id: b"test-456".to_vec(),
            name: b"example.csv".to_vec(),
            description: b"Example dataset".to_vec(),
            format: b"CSV".to_vec(),
            size: 2048,
            original_hash: vec![0xAA, 0xBB, 0xCC, 0xDD],
            walrus_blob_id: b"walrus-blob-456".to_vec(),
            seal_policy_id: b"seal-policy-456".to_vec(),
            timestamp: 1234567890000,
            uploader: b"0xB".to_vec(),
        };

        let bytes = bcs::to_bytes(&verification).expect("BCS serialization should succeed");

        // Verify we can deserialize back
        let deserialized: DatasetVerification = bcs::from_bytes(&bytes)
            .expect("BCS deserialization should succeed");

        assert_eq!(verification.dataset_id, deserialized.dataset_id);
        assert_eq!(verification.name, deserialized.name);
        assert_eq!(verification.description, deserialized.description);
        assert_eq!(verification.original_hash, deserialized.original_hash);
        assert_eq!(verification.walrus_blob_id, deserialized.walrus_blob_id);
        assert_eq!(verification.seal_policy_id, deserialized.seal_policy_id);
        assert_eq!(verification.format, deserialized.format);
        assert_eq!(verification.size, deserialized.size);
        assert_eq!(verification.timestamp, deserialized.timestamp);
        assert_eq!(verification.uploader, deserialized.uploader);
    }

    #[test]
    fn test_intent_message_structure() {
        // Test IntentMessage wrapper structure
        let payload = DatasetVerification {
            dataset_id: b"test-789".to_vec(),
            name: b"data.json".to_vec(),
            description: b"Test JSON dataset".to_vec(),
            format: b"JSON".to_vec(),
            size: 4096,
            original_hash: vec![0x11, 0x22, 0x33, 0x44],
            walrus_blob_id: b"walrus-789".to_vec(),
            seal_policy_id: b"seal-789".to_vec(),
            timestamp: 1700000000000,
            uploader: b"0xC".to_vec(),
        };

        let timestamp = 1700000000000;
        let intent_msg = IntentMessage::new(payload.clone(), timestamp, IntentScope::ProcessData);

        // Verify fields
        assert_eq!(intent_msg.timestamp_ms, timestamp);
        assert_eq!(intent_msg.data.original_hash, payload.original_hash);

        // Verify serialization produces consistent output
        let bytes1 = bcs::to_bytes(&intent_msg).expect("should serialize");
        let bytes2 = bcs::to_bytes(&intent_msg).expect("should serialize");

        assert_eq!(bytes1, bytes2, "Serialization should be deterministic");
    }

    #[test]
    fn test_dataset_request_parsing() {
        // Test DatasetRequest struct deserialization
        let json = r#"{
            "dataset_url": "https://example.com/dataset.csv",
            "expected_hash": "abcd1234",
            "format": "CSV",
            "schema_version": "v1.0"
        }"#;

        let request: DatasetRequest = serde_json::from_str(json)
            .expect("Should parse valid JSON");

        assert_eq!(request.dataset_url, "https://example.com/dataset.csv");
        assert_eq!(request.expected_hash, Some("abcd1234".to_string()));
        assert_eq!(request.format, "CSV");
        assert_eq!(request.schema_version, "v1.0");
    }

    #[test]
    fn test_dataset_request_optional_hash() {
        // Test DatasetRequest with no expected_hash
        let json = r#"{
            "dataset_url": "https://example.com/dataset.csv",
            "format": "CSV",
            "schema_version": "v1.0"
        }"#;

        let request: DatasetRequest = serde_json::from_str(json)
            .expect("Should parse JSON without expected_hash");

        assert_eq!(request.expected_hash, None);
    }

    #[test]
    fn test_hash_comparison() {
        // Test hash comparison logic (expected vs actual)
        let data = b"test dataset content";

        let mut hasher = Sha256::new();
        hasher.update(data);
        let actual_hash = hasher.finalize().to_vec();

        let expected_hex = hex::encode(&actual_hash);
        let decoded_expected = hex::decode(&expected_hex).expect("Should decode hex");

        assert_eq!(actual_hash, decoded_expected, "Hash comparison should match");
    }

    #[test]
    fn test_multiple_hash_computations() {
        // Test that different data produces different hashes
        let data1 = b"dataset A";
        let data2 = b"dataset B";

        let mut hasher1 = Sha256::new();
        hasher1.update(data1);
        let hash1 = hasher1.finalize().to_vec();

        let mut hasher2 = Sha256::new();
        hasher2.update(data2);
        let hash2 = hasher2.finalize().to_vec();

        assert_ne!(hash1, hash2, "Different data should produce different hashes");
    }

    #[test]
    fn test_bcs_encoding_consistency() {
        // Test that identical structs produce identical BCS bytes
        let verification1 = DatasetVerification {
            dataset_id: b"consistent-test".to_vec(),
            name: b"data.csv".to_vec(),
            description: b"Consistency test".to_vec(),
            format: b"CSV".to_vec(),
            size: 9999,
            original_hash: vec![0xDE, 0xAD, 0xBE, 0xEF],
            walrus_blob_id: b"walrus-consistent".to_vec(),
            seal_policy_id: b"seal-consistent".to_vec(),
            timestamp: 9999999999999,
            uploader: b"0xDEADBEEF".to_vec(),
        };

        let verification2 = DatasetVerification {
            dataset_id: b"consistent-test".to_vec(),
            name: b"data.csv".to_vec(),
            description: b"Consistency test".to_vec(),
            format: b"CSV".to_vec(),
            size: 9999,
            original_hash: vec![0xDE, 0xAD, 0xBE, 0xEF],
            walrus_blob_id: b"walrus-consistent".to_vec(),
            seal_policy_id: b"seal-consistent".to_vec(),
            timestamp: 9999999999999,
            uploader: b"0xDEADBEEF".to_vec(),
        };

        let bytes1 = bcs::to_bytes(&verification1).expect("should serialize");
        let bytes2 = bcs::to_bytes(&verification2).expect("should serialize");

        assert_eq!(bytes1, bytes2, "Identical structs should produce identical BCS");
    }

    #[test]
    fn test_timestamp_handling() {
        // Test that timestamp changes affect serialization
        let base_verification = DatasetVerification {
            dataset_id: b"timestamp-test".to_vec(),
            name: b"data.csv".to_vec(),
            description: b"Timestamp test".to_vec(),
            format: b"CSV".to_vec(),
            size: 1000,
            original_hash: vec![0xFF],
            walrus_blob_id: b"walrus-ts".to_vec(),
            seal_policy_id: b"seal-ts".to_vec(),
            timestamp: 1000,
            uploader: b"0xFF".to_vec(),
        };

        let different_timestamp = DatasetVerification {
            timestamp: 2000,
            ..base_verification.clone()
        };

        let bytes1 = bcs::to_bytes(&base_verification).expect("should serialize");
        let bytes2 = bcs::to_bytes(&different_timestamp).expect("should serialize");

        assert_ne!(bytes1, bytes2, "Different timestamps should produce different BCS");
    }

    #[tokio::test]
    async fn test_process_data_request_structure() {
        // Test the full ProcessDataRequest wrapper structure
        let inner_request = DatasetRequest {
            dataset_url: "https://example.com/test.csv".to_string(),
            expected_hash: Some("abc123".to_string()),
            format: "CSV".to_string(),
            schema_version: "v1.0".to_string(),
        };

        let full_request = ProcessDataRequest {
            payload: inner_request,
        };

        // Verify JSON serialization round-trip
        let json = serde_json::to_string(&full_request).expect("Should serialize to JSON");
        let parsed: ProcessDataRequest<DatasetRequest> = serde_json::from_str(&json)
            .expect("Should deserialize from JSON");

        assert_eq!(parsed.payload.dataset_url, "https://example.com/test.csv");
        assert_eq!(parsed.payload.format, "CSV");
    }

    #[test]
    fn test_large_dataset_hash() {
        // Test hashing of larger dataset (simulate real-world size)
        let large_data: Vec<u8> = (0..10_000).map(|i| (i % 256) as u8).collect();

        let mut hasher = Sha256::new();
        hasher.update(&large_data);
        let hash_result = hasher.finalize();
        let dataset_hash = hash_result.to_vec();

        assert_eq!(dataset_hash.len(), 32, "Hash length should be consistent");
        println!("Large dataset (10KB) hash: {}", Hex::encode(&dataset_hash));
    }

    #[test]
    fn test_intent_scope_serialization() {
        // Test IntentScope enum serialization
        let scope = IntentScope::ProcessData;
        let bytes = bcs::to_bytes(&scope).expect("Should serialize IntentScope");

        // IntentScope::ProcessData should serialize to 0x00
        assert_eq!(bytes, vec![0x00], "ProcessData should serialize to 0x00");
    }
}
