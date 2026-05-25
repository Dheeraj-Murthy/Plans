use serde::{Serialize, Deserialize};
use crate::db;
use aes_gcm::{Aes256Gcm, Key, Nonce};
use aes_gcm::aead::{Aead, KeyInit};
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use sha2::{Digest, Sha256};
use rand::RngCore;
use std::io::{Read, Write};

#[derive(Debug, Serialize, Deserialize)]
pub struct SyncState {
    pub snapshot_version: i64,
    pub last_synced_at: Option<String>,
    pub last_remote_checksum: Option<String>,
    pub device_id: String,
    pub last_uploaded_version: i64,
}

pub fn get_sync_state() -> Result<SyncState, String> {
    db::with_db(|conn| {
        Ok(conn.query_row(
            "SELECT snapshot_version, last_synced_at, last_remote_checksum, device_id, last_uploaded_version \
             FROM sync_state WHERE id = 1", [],
            |row| Ok(SyncState {
                snapshot_version: row.get(0)?,
                last_synced_at: row.get(1)?,
                last_remote_checksum: row.get(2)?,
                device_id: row.get(3)?,
                last_uploaded_version: row.get(4)?,
            })
        )?)
    })
}

pub fn set_sync_state(state: &SyncState) -> Result<(), String> {
    db::with_db(|conn| {
        conn.execute(
            "UPDATE sync_state SET snapshot_version=?1, last_synced_at=?2, \
             last_remote_checksum=?3, device_id=?4, last_uploaded_version=?5 WHERE id=1",
            rusqlite::params![
                state.snapshot_version,
                state.last_synced_at,
                state.last_remote_checksum,
                state.device_id,
                state.last_uploaded_version,
            ],
        )?;
        Ok(())
    })
}

pub fn get_or_create_device_id() -> Result<String, String> {
    let mut state = get_sync_state()?;
    if state.device_id.is_empty() {
        state.device_id = uuid::Uuid::new_v4().to_string();
        set_sync_state(&state)?;
    }
    Ok(state.device_id)
}

pub struct SnapshotResult {
    pub encrypted: Vec<u8>,
    pub manifest_json: String,
}

pub fn create_snapshot(
    key: &[u8; 32],
    db_path: &str,
    device_id: &str,
    device_name: &str,
    schema_version: i64,
    app_version: &str,
) -> Result<SnapshotResult, String> {
    // 0. Increment snapshot_version atomically before backup
    //    so the DB state matches the manifest version.
    let mut state = get_sync_state()?;
    let new_version = state.snapshot_version + 1;
    state.snapshot_version = new_version;
    state.last_synced_at = Some(chrono::Utc::now().to_rfc3339());
    state.last_uploaded_version = new_version;
    set_sync_state(&state)?;

    // 1. Backup API -> temp file (consistent snapshot with minimal locking)
    let backup_path = format!("{}.sync_backup", db_path);
    db::with_db(|src| {
        let mut dst = rusqlite::Connection::open(&backup_path)?;
        let backup = rusqlite::backup::Backup::new(src, &mut dst)?;
        backup.run_to_completion(100, std::time::Duration::from_millis(250), None)?;
        Ok(())
    })?;

    // 2. Read backup bytes, clean up
    let db_bytes = std::fs::read(&backup_path).map_err(|e| e.to_string())?;
    std::fs::remove_file(&backup_path).ok();

    // 3. SHA-256 checksum of plaintext DB bytes
    let checksum = hex::encode(Sha256::digest(&db_bytes));

    // 4. gzip compress
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&db_bytes).map_err(|e| e.to_string())?;
    let compressed = encoder.finish().map_err(|e| e.to_string())?;

    // 5. AES-256-GCM encrypt
    let aes_key = Key::<Aes256Gcm>::from_slice(key);
    let cipher = Aes256Gcm::new(aes_key);
    let mut nonce_bytes = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, compressed.as_ref())
        .map_err(|e| format!("encryption failed: {:?}", e))?;

    // 6. Payload: nonce(12) || ciphertext
    let mut encrypted = Vec::with_capacity(12 + ciphertext.len());
    encrypted.extend_from_slice(&nonce_bytes);
    encrypted.extend_from_slice(&ciphertext);

    // 7. Build manifest JSON
    use chrono::Utc;
    let manifest = serde_json::json!({
        "snapshot_version": new_version,
        "device_id": device_id,
        "device_name": device_name,
        "checksum": checksum,
        "updated_at": Utc::now().to_rfc3339(),
        "schema_version": schema_version,
        "app_version": app_version,
        "row_count": 0,
    });

    Ok(SnapshotResult {
        encrypted,
        manifest_json: manifest.to_string(),
    })
}

pub fn install_snapshot(
    encrypted: &[u8],
    manifest_str: &str,
    key: &[u8; 32],
    db_path: &str,
) -> Result<i64, String> {
    // 1. Parse manifest
    let m: serde_json::Value = serde_json::from_str(manifest_str)
        .map_err(|e| format!("bad manifest: {}", e))?;
    let remote_ver = m["snapshot_version"]
        .as_i64()
        .ok_or("no snapshot_version")?;
    let expected_checksum = m["checksum"].as_str().ok_or("no checksum")?;

    // 2. Version gate -- prevent downgrade
    let cur = get_sync_state()?;
    if remote_ver <= cur.snapshot_version {
        return Err(format!(
            "remote v{} <= local v{}, skip",
            remote_ver, cur.snapshot_version
        ));
    }

    // 3. AES-256-GCM decrypt
    if encrypted.len() < 12 {
        return Err("encrypted data too short".into());
    }
    let (nonce_bytes, ct) = encrypted.split_at(12);
    let compressed = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key))
        .decrypt(Nonce::from_slice(nonce_bytes), ct)
        .map_err(|e| format!("decrypt failed: {:?}", e))?;

    // 4. gzip decompress
    let mut db_bytes = Vec::new();
    GzDecoder::new(compressed.as_slice())
        .read_to_end(&mut db_bytes)
        .map_err(|e| format!("decompress failed: {}", e))?;

    // 5. Verify checksum
    let actual = hex::encode(Sha256::digest(&db_bytes));
    if actual != expected_checksum {
        return Err(format!(
            "checksum mismatch: got {}, expected {}",
            actual, expected_checksum
        ));
    }

    // 6. Write to temp file + verify integrity
    let temp = format!("{}.sync_install", db_path);
    std::fs::write(&temp, &db_bytes).map_err(|e| e.to_string())?;
    let verify = rusqlite::Connection::open(&temp).map_err(|e| e.to_string())?;
    let integrity: String = verify
        .pragma_query_value(None, "integrity_check", |r| r.get(0))
        .map_err(|e| e.to_string())?;
    if !integrity.to_lowercase().contains("ok") {
        std::fs::remove_file(&temp).ok();
        return Err(format!("integrity check failed: {}", integrity));
    }

    // 6b. Verify snapshot version matches manifest version
    let db_ver: i64 = verify
        .query_row(
            "SELECT snapshot_version FROM sync_state WHERE id=1",
            [],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;
    if db_ver != remote_ver {
        std::fs::remove_file(&temp).ok();
        return Err(format!(
            "version mismatch: snapshot has v{}, manifest says v{}",
            db_ver, remote_ver
        ));
    }
    drop(verify);

    // 7. Lock DB mutex directly to drop + replace connection
    let mut db_guard = db::DB.lock().map_err(|e| e.to_string())?;
    *db_guard = None; // drop old connection

    // 8. Atomic rename
    std::fs::rename(&temp, db_path).map_err(|e| e.to_string())?;

    // 9. Reopen connection
    let conn = rusqlite::Connection::open(db_path).map_err(|e| e.to_string())?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        .map_err(|e| e.to_string())?;
    *db_guard = Some(conn);
    drop(db_guard);

    // 10. Update local sync_state
    let mut state = get_sync_state()?;
    state.snapshot_version = remote_ver;
    state.last_synced_at = Some(chrono::Utc::now().to_rfc3339());
    state.last_remote_checksum = Some(expected_checksum.to_string());
    set_sync_state(&state)?;

    Ok(remote_ver)
}
