pub mod projects;
pub mod tasks;
pub mod subtasks;
pub mod sync;

use crate::db;

pub fn init_database(path: String) -> Result<(), String> {
    db::init_db(&path)
}
