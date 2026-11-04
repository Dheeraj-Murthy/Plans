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
    #[serde(default)]
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Subtask {
    pub id: String,
    pub task_id: String,
    pub title: String,
    pub is_completed: bool,
    pub sort_order: i64,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubtaskCount {
    pub task_id: String,
    pub total: i64,
    pub completed: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExpenseCategory {
    pub id: String,
    pub name: String,
    pub color_index: i64,
    #[serde(default)]
    pub updated_at: i64,
}

/// `kind` is "topup" or "expense" — the DB column is named `type` (a Rust
/// keyword, so it can't be the field name here).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BudgetTransaction {
    pub id: String,
    pub kind: String,
    pub amount: f64,
    pub category_id: Option<String>,
    pub note: Option<String>,
    pub occurred_at: i64,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BudgetSettings {
    pub reset_at: i64,
    pub currency_symbol: String,
    pub updated_at: i64,
}
