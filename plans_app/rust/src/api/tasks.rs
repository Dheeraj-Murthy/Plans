use crate::db;
use crate::error::AppError;
use crate::models::Task;
use uuid::Uuid;

pub fn get_all_tasks() -> Result<Vec<Task>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, title, description, due_date, priority, is_completed, is_deleted, project_id, created_at, updated_at, sort_order, reminder_minutes, recurrence \
             FROM tasks WHERE is_deleted = 0 ORDER BY sort_order ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(Task {
                id: row.get(0)?,
                title: row.get(1)?,
                description: row.get(2)?,
                due_date: row.get(3)?,
                priority: row.get(4)?,
                is_completed: row.get::<_, i64>(5)? == 1,
                is_deleted: row.get::<_, i64>(6)? == 1,
                project_id: row.get(7)?,
                created_at: row.get(8)?,
                updated_at: row.get(9)?,
                sort_order: row.get(10)?,
                reminder_minutes: row.get(11)?,
                recurrence: row.get(12)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_task(
    title: String,
    description: Option<String>,
    due_date: Option<i64>,
    priority: i64,
    project_id: String,
    reminder_minutes: Option<i64>,
    recurrence: Option<String>,
) -> Result<Task, String> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    db::with_db(|conn| {
        let max_order: i64 = conn
            .query_row("SELECT COALESCE(MAX(sort_order), -1) FROM tasks WHERE is_deleted = 0", [], |r| r.get(0))?;
        let sort_order = max_order + 1;
        let task = Task {
            id,
            title,
            description,
            due_date,
            priority,
            is_completed: false,
            is_deleted: false,
            project_id,
            created_at: now,
            updated_at: now,
            sort_order,
            reminder_minutes,
            recurrence,
        };
        conn.execute(
            "INSERT INTO tasks (id, title, description, due_date, priority, is_completed, project_id, created_at, updated_at, sort_order, reminder_minutes, recurrence) \
             VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?7, ?8, ?9, ?10, ?11)",
            rusqlite::params![task.id, task.title, task.description, task.due_date, task.priority, task.project_id, task.created_at, task.updated_at, task.sort_order, task.reminder_minutes, task.recurrence],
        )?;
        Ok(task)
    })
}

pub fn update_task(task_json: String) -> Result<Task, String> {
    let task: Task = serde_json::from_str(&task_json).map_err(|e| AppError::Json(e).to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "UPDATE tasks SET title=?1, description=?2, due_date=?3, priority=?4, is_completed=?5, project_id=?6, updated_at=?7, sort_order=?9, reminder_minutes=?10, recurrence=?11 WHERE id=?8",
            rusqlite::params![task.title, task.description, task.due_date, task.priority, task.is_completed as i64, task.project_id, chrono::Utc::now().timestamp_millis(), task.id, task.sort_order, task.reminder_minutes, task.recurrence],
        )?;
        Ok(task)
    })
}

pub fn reorder_tasks(task_ids: Vec<String>) -> Result<(), String> {
    db::with_db(|conn| {
        for (i, id) in task_ids.iter().enumerate() {
            conn.execute(
                "UPDATE tasks SET sort_order=?1, updated_at=?2 WHERE id=?3",
                rusqlite::params![i as i64, chrono::Utc::now().timestamp_millis(), id],
            )?;
        }
        Ok(())
    })
}

pub fn delete_task(id: String) -> Result<(), String> {
    db::with_db(|conn| {
        conn.execute(
            "UPDATE tasks SET is_deleted=1, updated_at=?1 WHERE id=?2",
            rusqlite::params![chrono::Utc::now().timestamp_millis(), id],
        )?;
        Ok(())
    })
}

pub fn clear_completed() -> Result<(), String> {
    db::with_db(|conn| {
        conn.execute(
            "UPDATE tasks SET is_deleted=1, updated_at=?1 WHERE is_deleted=0 AND is_completed=1",
            rusqlite::params![chrono::Utc::now().timestamp_millis()],
        )?;
        Ok(())
    })
}

pub fn restore_task(id: String) -> Result<(), String> {
    db::with_db(|conn| {
        conn.execute(
            "UPDATE tasks SET is_deleted=0, updated_at=?1 WHERE id=?2",
            rusqlite::params![chrono::Utc::now().timestamp_millis(), id],
        )?;
        Ok(())
    })
}

/// Last-write-wins upsert by updated_at. Used when merging local data after
/// installing a remote snapshot — preserves whichever version is newer.
pub fn upsert_task(task_json: String) -> Result<(), String> {
    let task: Task = serde_json::from_str(&task_json).map_err(|e| AppError::Json(e).to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO tasks (id, title, description, due_date, priority, is_completed, is_deleted, project_id, created_at, updated_at, sort_order, reminder_minutes, recurrence)
             VALUES (?1,?2,?3,?4,?5,?6,?13,?7,?8,?9,?10,?11,?12)
             ON CONFLICT(id) DO UPDATE SET
               title            = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.title            ELSE tasks.title            END,
               description      = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.description      ELSE tasks.description      END,
               due_date         = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.due_date         ELSE tasks.due_date         END,
               priority         = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.priority         ELSE tasks.priority         END,
               is_completed     = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.is_completed     ELSE tasks.is_completed     END,
               is_deleted       = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.is_deleted       ELSE tasks.is_deleted       END,
               project_id       = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.project_id       ELSE tasks.project_id       END,
               updated_at       = MAX(excluded.updated_at, tasks.updated_at),
               sort_order       = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.sort_order       ELSE tasks.sort_order       END,
               reminder_minutes = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.reminder_minutes ELSE tasks.reminder_minutes END,
               recurrence       = CASE WHEN excluded.updated_at > tasks.updated_at THEN excluded.recurrence       ELSE tasks.recurrence       END",
            rusqlite::params![
                task.id, task.title, task.description, task.due_date,
                task.priority, task.is_completed as i64,
                task.project_id, task.created_at, task.updated_at,
                task.sort_order, task.reminder_minutes, task.recurrence,
                task.is_deleted as i64
            ],
        )?;
        Ok(())
    })
}
