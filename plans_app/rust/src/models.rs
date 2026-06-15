use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub description: Option<String>,
    pub due_date: Option<i64>,
    pub priority: i64,
    pub is_completed: bool,
    #[serde(default)]
    pub is_deleted: bool,
    pub project_id: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub sort_order: i64,
    #[serde(default)]
    pub reminder_minutes: Option<i64>,
    #[serde(default)]
    pub recurrence: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub color_index: i64,
}
