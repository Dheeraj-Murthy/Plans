use crate::db;
use crate::models::{BudgetSettings, BudgetTransaction, ExpenseCategory};
use uuid::Uuid;

// ── Expense categories ──────────────────────────────────────────────────

pub fn get_expense_categories() -> Result<Vec<ExpenseCategory>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, name, color_index, updated_at FROM expense_categories WHERE is_deleted = 0 ORDER BY color_index ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(ExpenseCategory {
                id: row.get(0)?,
                name: row.get(1)?,
                color_index: row.get(2)?,
                updated_at: row.get(3)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_expense_category(name: String, color_index: i64) -> Result<ExpenseCategory, String> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    let category = ExpenseCategory { id, name, color_index, updated_at: now };
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO expense_categories (id, name, color_index, is_deleted, created_at, updated_at) VALUES (?1, ?2, ?3, 0, ?4, ?4)",
            rusqlite::params![category.id, category.name, category.color_index, category.updated_at],
        )?;
        Ok(category)
    })
}

pub fn update_expense_category(id: String, name: String, color_index: i64) -> Result<ExpenseCategory, String> {
    if id == "other" {
        return Err("The Other category cannot be renamed".to_string());
    }
    let now = chrono::Utc::now().timestamp_millis();
    let category = ExpenseCategory { id, name, color_index, updated_at: now };
    db::with_db(|conn| {
        conn.execute(
            "UPDATE expense_categories SET name=?1, color_index=?2, updated_at=?3 WHERE id=?4",
            rusqlite::params![category.name, category.color_index, category.updated_at, category.id],
        )?;
        Ok(category)
    })
}

pub fn delete_expense_category(id: String) -> Result<(), String> {
    if id == "other" {
        return Err("The Other category cannot be deleted".to_string());
    }
    db::with_db(|conn| {
        let now = chrono::Utc::now().timestamp_millis();
        let tx = conn.unchecked_transaction()?;
        tx.execute(
            "UPDATE budget_transactions SET category_id='other', updated_at=?1 WHERE category_id=?2 AND is_deleted=0",
            rusqlite::params![now, id],
        )?;
        tx.execute(
            "UPDATE expense_categories SET is_deleted=1, updated_at=?1 WHERE id=?2",
            rusqlite::params![now, id],
        )?;
        tx.commit()?;
        Ok(())
    })
}

/// Last-write-wins upsert by updated_at — same shape as upsert_project, used
/// when merging local data after installing a remote sync snapshot.
pub fn upsert_expense_category(category_json: String) -> Result<(), String> {
    let category: ExpenseCategory = serde_json::from_str(&category_json).map_err(|e| e.to_string())?;
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO expense_categories (id, name, color_index, is_deleted, created_at, updated_at)
             VALUES (?1, ?2, ?3, 0, ?4, ?4)
             ON CONFLICT(id) DO UPDATE SET
               name        = CASE WHEN excluded.updated_at > expense_categories.updated_at THEN excluded.name        ELSE expense_categories.name        END,
               color_index = CASE WHEN excluded.updated_at > expense_categories.updated_at THEN excluded.color_index ELSE expense_categories.color_index END,
               updated_at  = MAX(excluded.updated_at, expense_categories.updated_at)",
            rusqlite::params![category.id, category.name, category.color_index, now],
        )?;
        Ok(())
    })
}

// ── Budget transactions (top-ups + expenses, one ledger) ───────────────

fn row_to_transaction(row: &rusqlite::Row) -> rusqlite::Result<BudgetTransaction> {
    Ok(BudgetTransaction {
        id: row.get(0)?,
        kind: row.get(1)?,
        amount: row.get(2)?,
        category_id: row.get(3)?,
        note: row.get(4)?,
        occurred_at: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

const TRANSACTION_COLUMNS: &str =
    "id, type, amount, category_id, note, occurred_at, created_at, updated_at";

pub fn get_budget_transactions() -> Result<Vec<BudgetTransaction>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(&format!(
            "SELECT {TRANSACTION_COLUMNS} FROM budget_transactions WHERE is_deleted = 0 ORDER BY occurred_at DESC",
        ))?;
        let rows = stmt.query_map([], row_to_transaction)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_budget_transaction(
    kind: String,
    amount: f64,
    category_id: Option<String>,
    note: Option<String>,
    occurred_at: i64,
) -> Result<BudgetTransaction, String> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    let effective_category = if kind == "expense" {
        Some(category_id.unwrap_or_else(|| "other".to_string()))
    } else {
        None
    };
    let transaction = BudgetTransaction {
        id,
        kind,
        amount,
        category_id: effective_category,
        note,
        occurred_at,
        created_at: now,
        updated_at: now,
    };
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO budget_transactions (id, type, amount, category_id, note, occurred_at, is_deleted, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?8)",
            rusqlite::params![
                transaction.id,
                transaction.kind,
                transaction.amount,
                transaction.category_id,
                transaction.note,
                transaction.occurred_at,
                transaction.created_at,
                transaction.updated_at,
            ],
        )?;
        Ok(transaction)
    })
}

pub fn update_budget_transaction(transaction_json: String) -> Result<(), String> {
    let t: BudgetTransaction = serde_json::from_str(&transaction_json).map_err(|e| e.to_string())?;
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        conn.execute(
            "UPDATE budget_transactions SET type=?1, amount=?2, category_id=?3, note=?4, occurred_at=?5, updated_at=?6 WHERE id=?7",
            rusqlite::params![t.kind, t.amount, t.category_id, t.note, t.occurred_at, now, t.id],
        )?;
        Ok(())
    })
}

pub fn delete_budget_transaction(id: String) -> Result<(), String> {
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        conn.execute(
            "UPDATE budget_transactions SET is_deleted=1, updated_at=?1 WHERE id=?2",
            rusqlite::params![now, id],
        )?;
        Ok(())
    })
}

/// Last-write-wins upsert by updated_at — same shape as upsert_task, used
/// when merging local data after installing a remote sync snapshot.
pub fn upsert_budget_transaction(transaction_json: String) -> Result<(), String> {
    let t: BudgetTransaction = serde_json::from_str(&transaction_json).map_err(|e| e.to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO budget_transactions (id, type, amount, category_id, note, occurred_at, is_deleted, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?7)
             ON CONFLICT(id) DO UPDATE SET
               type         = CASE WHEN excluded.updated_at > budget_transactions.updated_at THEN excluded.type         ELSE budget_transactions.type         END,
               amount       = CASE WHEN excluded.updated_at > budget_transactions.updated_at THEN excluded.amount       ELSE budget_transactions.amount       END,
               category_id  = CASE WHEN excluded.updated_at > budget_transactions.updated_at THEN excluded.category_id  ELSE budget_transactions.category_id  END,
               note         = CASE WHEN excluded.updated_at > budget_transactions.updated_at THEN excluded.note         ELSE budget_transactions.note         END,
               occurred_at  = CASE WHEN excluded.updated_at > budget_transactions.updated_at THEN excluded.occurred_at  ELSE budget_transactions.occurred_at  END,
               updated_at   = MAX(excluded.updated_at, budget_transactions.updated_at)",
            rusqlite::params![
                t.id, t.kind, t.amount, t.category_id, t.note, t.occurred_at, t.updated_at,
            ],
        )?;
        Ok(())
    })
}

// ── Budget settings (singleton: reset point + currency symbol) ─────────

pub fn get_budget_settings() -> Result<BudgetSettings, String> {
    db::with_db(|conn| {
        conn.query_row(
            "SELECT reset_at, currency_symbol, updated_at FROM budget_settings WHERE id = 1",
            [],
            |row| {
                Ok(BudgetSettings {
                    reset_at: row.get(0)?,
                    currency_symbol: row.get(1)?,
                    updated_at: row.get(2)?,
                })
            },
        )
        .map_err(Into::into)
    })
}

pub fn update_budget_settings(currency_symbol: String) -> Result<BudgetSettings, String> {
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        conn.execute(
            "UPDATE budget_settings SET currency_symbol=?1, updated_at=?2 WHERE id=1",
            rusqlite::params![currency_symbol, now],
        )?;
        Ok(())
    })?;
    get_budget_settings()
}

/// Moves the running-balance start point to now. History isn't deleted —
/// only transactions on/after this point count toward the balance going
/// forward.
pub fn reset_budget() -> Result<i64, String> {
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        conn.execute(
            "UPDATE budget_settings SET reset_at=?1, updated_at=?1 WHERE id=1",
            rusqlite::params![now],
        )?;
        Ok(())
    })?;
    Ok(now)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_support::init_test_db;

    #[test]
    fn other_category_cannot_be_renamed_or_deleted() {
        let _db = init_test_db();
        let err = update_expense_category("other".to_string(), "Renamed".to_string(), 5).unwrap_err();
        assert!(err.contains("Other"));
        let err = delete_expense_category("other".to_string()).unwrap_err();
        assert!(err.contains("Other"));
    }

    #[test]
    fn deleting_category_reassigns_its_transactions_to_other() {
        let _db = init_test_db();
        let category = create_expense_category("Pets".to_string(), 1).unwrap();
        let t = create_budget_transaction(
            "expense".to_string(),
            50.0,
            Some(category.id.clone()),
            Some("Vet".to_string()),
            chrono::Utc::now().timestamp_millis(),
        )
        .unwrap();

        delete_expense_category(category.id).unwrap();

        let after = get_budget_transactions()
            .unwrap()
            .into_iter()
            .find(|x| x.id == t.id)
            .unwrap();
        assert_eq!(after.category_id, Some("other".to_string()));
    }

    #[test]
    fn expense_without_category_defaults_to_other() {
        let _db = init_test_db();
        let t = create_budget_transaction(
            "expense".to_string(),
            20.0,
            None,
            None,
            chrono::Utc::now().timestamp_millis(),
        )
        .unwrap();
        assert_eq!(t.category_id, Some("other".to_string()));
    }

    #[test]
    fn topup_has_no_category() {
        let _db = init_test_db();
        let t = create_budget_transaction(
            "topup".to_string(),
            1000.0,
            None,
            Some("Salary".to_string()),
            chrono::Utc::now().timestamp_millis(),
        )
        .unwrap();
        assert_eq!(t.category_id, None);
    }

    #[test]
    fn reset_budget_moves_reset_at_forward() {
        let _db = init_test_db();
        let before = get_budget_settings().unwrap();
        assert_eq!(before.reset_at, 0);
        let new_reset_at = reset_budget().unwrap();
        assert!(new_reset_at > 0);
        let after = get_budget_settings().unwrap();
        assert_eq!(after.reset_at, new_reset_at);
    }

    #[test]
    fn upsert_budget_transaction_is_last_write_wins() {
        let _db = init_test_db();
        let created = create_budget_transaction(
            "expense".to_string(),
            100.0,
            None,
            Some("Original".to_string()),
            1_000,
        )
        .unwrap();

        let stale = serde_json::json!({
            "id": created.id,
            "kind": "expense",
            "amount": 999.0,
            "category_id": "other",
            "note": "Stale",
            "occurred_at": 1_000,
            "created_at": created.created_at,
            "updated_at": created.updated_at - 10_000,
        });
        upsert_budget_transaction(stale.to_string()).unwrap();
        let after_stale = get_budget_transactions()
            .unwrap()
            .into_iter()
            .find(|x| x.id == created.id)
            .unwrap();
        assert_eq!(after_stale.note, Some("Original".to_string()));

        let fresh = serde_json::json!({
            "id": created.id,
            "kind": "expense",
            "amount": 50.0,
            "category_id": "other",
            "note": "Fresh",
            "occurred_at": 1_000,
            "created_at": created.created_at,
            "updated_at": created.updated_at + 10_000,
        });
        upsert_budget_transaction(fresh.to_string()).unwrap();
        let after_fresh = get_budget_transactions()
            .unwrap()
            .into_iter()
            .find(|x| x.id == created.id)
            .unwrap();
        assert_eq!(after_fresh.note, Some("Fresh".to_string()));
    }
}
