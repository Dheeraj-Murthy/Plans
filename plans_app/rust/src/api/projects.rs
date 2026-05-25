use crate::db;
use crate::models::Project;
use uuid::Uuid;

pub fn get_all_projects() -> Result<Vec<Project>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, name, color_index FROM projects WHERE is_deleted = 0 ORDER BY color_index ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(Project {
                id: row.get(0)?,
                name: row.get(1)?,
                color_index: row.get(2)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_project(name: String, color_index: i64) -> Result<Project, String> {
    let id = Uuid::new_v4().to_string();
    let project = Project { id, name, color_index };
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted) VALUES (?1, ?2, ?3, 0)",
            rusqlite::params![project.id, project.name, project.color_index],
        )?;
        Ok(project)
    })
}

pub fn update_project(id: String, name: String, color_index: i64) -> Result<Project, String> {
    let project = Project { id, name, color_index };
    db::with_db(|conn| {
        conn.execute(
            "UPDATE projects SET name=?1, color_index=?2 WHERE id=?3",
            rusqlite::params![project.name, project.color_index, project.id],
        )?;
        Ok(project)
    })
}

pub fn delete_project(id: String) -> Result<(), String> {
    db::with_db(|conn| {
        let now = chrono::Utc::now().timestamp_millis();
        let tx = conn.unchecked_transaction()?;
        tx.execute(
            "UPDATE tasks SET project_id='default', updated_at=?1 WHERE project_id=?2 AND is_deleted=0",
            rusqlite::params![now, id],
        )?;
        tx.execute(
            "UPDATE projects SET is_deleted=1 WHERE id=?1",
            rusqlite::params![id],
        )?;
        tx.commit()?;
        Ok(())
    })
}

/// Upsert a project from local state into the current DB.
/// Inserts if absent; updates name/color_index if present without touching is_deleted.
pub fn upsert_project(project_json: String) -> Result<(), String> {
    let project: Project = serde_json::from_str(&project_json).map_err(|e| e.to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted)
             VALUES (?1, ?2, ?3, 0)
             ON CONFLICT(id) DO UPDATE SET
               name        = excluded.name,
               color_index = excluded.color_index",
            rusqlite::params![project.id, project.name, project.color_index],
        )?;
        Ok(())
    })
}
