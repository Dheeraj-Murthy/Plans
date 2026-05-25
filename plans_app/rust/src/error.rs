use std::fmt;

#[derive(Debug)]
pub enum AppError {
    Db(rusqlite::Error),
    Json(serde_json::Error),
    Lock(String),
    NotInitialized,
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::Db(e) => write!(f, "Database error: {e}"),
            AppError::Json(e) => write!(f, "JSON error: {e}"),
            AppError::Lock(e) => write!(f, "Lock poisoned: {e}"),
            AppError::NotInitialized => write!(f, "Database not initialized"),
        }
    }
}

impl From<rusqlite::Error> for AppError {
    fn from(e: rusqlite::Error) -> Self {
        AppError::Db(e)
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::Json(e)
    }
}
