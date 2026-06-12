use rusqlite::Connection;
use std::sync::{LazyLock, Mutex};
use crate::error::AppError;

pub(crate) static DB: LazyLock<Mutex<Option<Connection>>> = LazyLock::new(|| Mutex::new(None));

pub fn init_db(path: &str) -> Result<(), String> {
    _init_db(path).map_err(|e| e.to_string())
}

fn _init_db(path: &str) -> Result<(), AppError> {
    let conn = Connection::open(path)?;
    conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
    run_migrations(&conn)?;
    let mut db = DB.lock().map_err(|e| AppError::Lock(e.to_string()))?;
    *db = Some(conn);
    Ok(())
}

fn run_migrations(conn: &Connection) -> Result<(), AppError> {
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            due_date INTEGER,
            priority INTEGER NOT NULL DEFAULT 0,
            is_completed INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            project_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            recurrence TEXT
        );
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color_index INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS changes (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT,
            timestamp INTEGER NOT NULL
        );",
    )?;

    // Idempotent column additions — "duplicate column" errors expected on existing DBs.
    conn.execute_batch("ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;")
        .ok();
    conn.execute_batch("ALTER TABLE tasks ADD COLUMN reminder_minutes INTEGER;")
        .ok();
    conn.execute_batch("ALTER TABLE tasks ADD COLUMN recurrence TEXT;")
        .ok();
    // IF NOT EXISTS / INSERT OR IGNORE — safe to discard result.
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS sync_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            snapshot_version INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT,
            last_remote_checksum TEXT,
            device_id TEXT NOT NULL DEFAULT '',
            last_uploaded_version INTEGER DEFAULT 0
        );"
    ).ok();
    conn.execute_batch(
        "INSERT OR IGNORE INTO sync_state (id, snapshot_version) VALUES (1, 0);"
    ).ok();

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM projects WHERE is_deleted = 0", [], |r| {
            r.get(0)
        })?;
    if count == 0 {
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted) VALUES (?1, ?2, ?3, 0)",
            rusqlite::params!["default", "Inbox", 0],
        )
        .ok();
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted) VALUES (?1, ?2, ?3, 0)",
            rusqlite::params!["work", "Work", 1],
        )
        .ok();
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted) VALUES (?1, ?2, ?3, 0)",
            rusqlite::params!["personal", "Personal", 2],
        )
        .ok();
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted) VALUES (?1, ?2, ?3, 0)",
            rusqlite::params!["ideas", "Ideas", 3],
        )
        .ok();
    }
    Ok(())
}

pub fn with_db<F, T>(f: F) -> Result<T, String>
where
    F: FnOnce(&Connection) -> Result<T, AppError>,
{
    let guard = DB.lock().map_err(|e| AppError::Lock(e.to_string()).to_string())?;
    let conn = guard.as_ref().ok_or_else(|| AppError::NotInitialized.to_string())?;
    f(conn).map_err(|e| e.to_string())
}
