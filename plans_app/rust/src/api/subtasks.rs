use crate::db;
use crate::error::AppError;
use crate::models::{Subtask, SubtaskCount};
use uuid::Uuid;

pub fn get_subtasks(task_id: String) -> Result<Vec<Subtask>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, task_id, title, is_completed, sort_order, created_at, updated_at \
             FROM subtasks WHERE task_id = ?1 ORDER BY sort_order ASC",
        )?;
        let rows = stmt.query_map(rusqlite::params![task_id], |row| {
            Ok(Subtask {
                id: row.get(0)?,
                task_id: row.get(1)?,
                title: row.get(2)?,
                is_completed: row.get::<_, i64>(3)? == 1,
                sort_order: row.get(4)?,
                created_at: row.get(5)?,
                updated_at: row.get(6)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

/// One grouped query for every task's subtask progress, so the task list can
/// show "n/m" without an N+1 query per task.
pub fn get_subtask_counts() -> Result<Vec<SubtaskCount>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT task_id, COUNT(*), SUM(is_completed) FROM subtasks GROUP BY task_id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(SubtaskCount {
                task_id: row.get(0)?,
                total: row.get(1)?,
                completed: row.get(2)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_subtask(task_id: String, title: String) -> Result<Subtask, String> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        let max_order: i64 = conn.query_row(
            "SELECT COALESCE(MAX(sort_order), -1) FROM subtasks WHERE task_id = ?1",
            rusqlite::params![task_id],
            |r| r.get(0),
        )?;
        let subtask = Subtask {
            id,
            task_id,
            title,
            is_completed: false,
            sort_order: max_order + 1,
            created_at: now,
            updated_at: now,
        };
        conn.execute(
            "INSERT INTO subtasks (id, task_id, title, is_completed, sort_order, created_at, updated_at) \
             VALUES (?1, ?2, ?3, 0, ?4, ?5, ?6)",
            rusqlite::params![
                subtask.id, subtask.task_id, subtask.title,
                subtask.sort_order, subtask.created_at, subtask.updated_at
            ],
        )?;
        Ok(subtask)
    })
}

pub fn update_subtask(subtask_json: String) -> Result<Subtask, String> {
    let subtask: Subtask =
        serde_json::from_str(&subtask_json).map_err(|e| AppError::Json(e).to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "UPDATE subtasks SET title=?1, is_completed=?2, updated_at=?3 WHERE id=?4",
            rusqlite::params![
                subtask.title,
                subtask.is_completed as i64,
                chrono::Utc::now().timestamp_millis(),
                subtask.id
            ],
        )?;
        Ok(subtask)
    })
}

pub fn delete_subtask(id: String) -> Result<(), String> {
    db::with_db(|conn| {
        conn.execute("DELETE FROM subtasks WHERE id=?1", rusqlite::params![id])?;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_support::init_test_db;
    use crate::api::tasks::create_task;

    fn make_task() -> String {
        create_task("Parent".to_string(), None, None, 0, "default".to_string(), None, None)
            .unwrap()
            .id
    }

    #[test]
    fn create_and_list_subtasks_in_order() {
        let _db = init_test_db();
        let task_id = make_task();
        create_subtask(task_id.clone(), "First".to_string()).unwrap();
        create_subtask(task_id.clone(), "Second".to_string()).unwrap();

        let subtasks = get_subtasks(task_id).unwrap();
        assert_eq!(subtasks.len(), 2);
        assert_eq!(subtasks[0].title, "First");
        assert_eq!(subtasks[1].title, "Second");
    }

    #[test]
    fn update_subtask_toggles_completion() {
        let _db = init_test_db();
        let task_id = make_task();
        let created = create_subtask(task_id.clone(), "Buy milk".to_string()).unwrap();

        let mut updated = created.clone();
        updated.is_completed = true;
        update_subtask(serde_json::to_string(&updated).unwrap()).unwrap();

        let subtasks = get_subtasks(task_id).unwrap();
        assert!(subtasks[0].is_completed);
    }

    #[test]
    fn delete_subtask_removes_it() {
        let _db = init_test_db();
        let task_id = make_task();
        let created = create_subtask(task_id.clone(), "Temp".to_string()).unwrap();
        delete_subtask(created.id).unwrap();

        assert!(get_subtasks(task_id).unwrap().is_empty());
    }

    #[test]
    fn subtask_counts_grouped_per_task() {
        let _db = init_test_db();
        let task_a = make_task();
        let task_b = make_task();

        let s1 = create_subtask(task_a.clone(), "A1".to_string()).unwrap();
        create_subtask(task_a.clone(), "A2".to_string()).unwrap();
        create_subtask(task_b.clone(), "B1".to_string()).unwrap();

        let mut done = s1.clone();
        done.is_completed = true;
        update_subtask(serde_json::to_string(&done).unwrap()).unwrap();

        let counts = get_subtask_counts().unwrap();
        let a = counts.iter().find(|c| c.task_id == task_a).unwrap();
        let b = counts.iter().find(|c| c.task_id == task_b).unwrap();
        assert_eq!((a.total, a.completed), (2, 1));
        assert_eq!((b.total, b.completed), (1, 0));
    }
}
