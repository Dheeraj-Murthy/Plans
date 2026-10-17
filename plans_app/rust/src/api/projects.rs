use crate::db;
use crate::models::Project;
use uuid::Uuid;

pub fn get_all_projects() -> Result<Vec<Project>, String> {
    db::with_db(|conn| {
        let mut stmt = conn.prepare(
            "SELECT id, name, color_index, updated_at FROM projects WHERE is_deleted = 0 ORDER BY color_index ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(Project {
                id: row.get(0)?,
                name: row.get(1)?,
                color_index: row.get(2)?,
                updated_at: row.get(3)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    })
}

pub fn create_project(name: String, color_index: i64) -> Result<Project, String> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    let project = Project { id, name, color_index, updated_at: now };
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted, updated_at) VALUES (?1, ?2, ?3, 0, ?4)",
            rusqlite::params![project.id, project.name, project.color_index, project.updated_at],
        )?;
        Ok(project)
    })
}

pub fn update_project(id: String, name: String, color_index: i64) -> Result<Project, String> {
    if id == "default" {
        return Err("The Inbox project cannot be renamed".to_string());
    }
    let now = chrono::Utc::now().timestamp_millis();
    let project = Project { id, name, color_index, updated_at: now };
    db::with_db(|conn| {
        conn.execute(
            "UPDATE projects SET name=?1, color_index=?2, updated_at=?3 WHERE id=?4",
            rusqlite::params![project.name, project.color_index, project.updated_at, project.id],
        )?;
        Ok(project)
    })
}

pub fn delete_project(id: String) -> Result<(), String> {
    if id == "default" {
        return Err("The Inbox project cannot be deleted".to_string());
    }
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

/// Last-write-wins upsert by updated_at, mirroring upsert_task. Used when
/// merging local data after installing a remote snapshot — preserves
/// whichever version is newer and never resurrects a deleted project.
pub fn upsert_project(project_json: String) -> Result<(), String> {
    let project: Project = serde_json::from_str(&project_json).map_err(|e| e.to_string())?;
    db::with_db(|conn| {
        conn.execute(
            "INSERT INTO projects (id, name, color_index, is_deleted, updated_at)
             VALUES (?1, ?2, ?3, 0, ?4)
             ON CONFLICT(id) DO UPDATE SET
               name        = CASE WHEN excluded.updated_at > projects.updated_at THEN excluded.name        ELSE projects.name        END,
               color_index = CASE WHEN excluded.updated_at > projects.updated_at THEN excluded.color_index ELSE projects.color_index END,
               updated_at  = MAX(excluded.updated_at, projects.updated_at)",
            rusqlite::params![project.id, project.name, project.color_index, project.updated_at],
        )?;
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_support::init_test_db;

    #[test]
    fn default_project_cannot_be_renamed() {
        let _db = init_test_db();
        let err = update_project("default".to_string(), "Renamed".to_string(), 5).unwrap_err();
        assert!(err.contains("Inbox"));
    }

    #[test]
    fn default_project_cannot_be_deleted() {
        let _db = init_test_db();
        let err = delete_project("default".to_string()).unwrap_err();
        assert!(err.contains("Inbox"));
        // Still present and active afterwards.
        let projects = get_all_projects().unwrap();
        assert!(projects.iter().any(|p| p.id == "default"));
    }

    #[test]
    fn upsert_project_is_last_write_wins() {
        let _db = init_test_db();
        let created = create_project("Original".to_string(), 1).unwrap();

        // Stale local update (older updated_at) must not clobber current data.
        let stale = serde_json::json!({
            "id": created.id,
            "name": "Stale",
            "color_index": 9,
            "updated_at": created.updated_at - 10_000,
        });
        upsert_project(stale.to_string()).unwrap();
        let after_stale = get_all_projects()
            .unwrap()
            .into_iter()
            .find(|p| p.id == created.id)
            .unwrap();
        assert_eq!(after_stale.name, "Original");

        // Newer update must win.
        let fresh = serde_json::json!({
            "id": created.id,
            "name": "Fresh",
            "color_index": 2,
            "updated_at": created.updated_at + 10_000,
        });
        upsert_project(fresh.to_string()).unwrap();
        let after_fresh = get_all_projects()
            .unwrap()
            .into_iter()
            .find(|p| p.id == created.id)
            .unwrap();
        assert_eq!(after_fresh.name, "Fresh");
    }
}
