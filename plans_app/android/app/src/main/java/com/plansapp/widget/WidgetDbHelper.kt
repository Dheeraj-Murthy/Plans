package com.plansapp.widget

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log

data class WidgetTask(
    val id: String,
    val title: String,
    val dueDate: Long?,
    val priority: Int,
    val isCompleted: Boolean,
    val projectId: String,
    val subtaskTotal: Int,
    val subtaskCompleted: Int,
)

data class WidgetProject(
    val id: String,
    val name: String,
    val colorIndex: Int,
)

class WidgetDbHelper private constructor(context: Context) {
    companion object {
        private const val TAG = "PlansWidget"
        private var instance: WidgetDbHelper? = null

        @Synchronized
        fun getInstance(context: Context): WidgetDbHelper {
            if (instance == null) {
                instance = WidgetDbHelper(context)
            }
            return instance!!
        }
    }

    private val dbPath: String =
        "${context.getDir("flutter", Context.MODE_PRIVATE).absolutePath}/plans.db"

    private var readDb: SQLiteDatabase? = null
    private var writeDb: SQLiteDatabase? = null

    private fun getReadDb(): SQLiteDatabase {
        if (readDb == null || !readDb!!.isOpen) {
            readDb = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READONLY)
        }
        return readDb!!
    }

    private fun getWriteDb(): SQLiteDatabase {
        if (writeDb == null || !writeDb!!.isOpen) {
            writeDb = SQLiteDatabase.openDatabase(dbPath, null, SQLiteDatabase.OPEN_READWRITE)
        }
        return writeDb!!
    }

    // LEFT JOINed against a per-task subtask count subquery so the widget
    // can render the same "n/m" progress chip the in-app task list shows —
    // without this join, a task's subtask_total/subtask_completed are
    // always absent from the widget's data and the chip never appears there.
    private val taskSelectWithSubtasks =
        "SELECT t.id, t.title, t.due_date, t.priority, t.is_completed, t.project_id, " +
            "COALESCE(sc.total, 0) AS subtask_total, COALESCE(sc.completed, 0) AS subtask_completed " +
            "FROM tasks t LEFT JOIN (SELECT task_id, COUNT(*) AS total, SUM(is_completed) AS completed FROM subtasks GROUP BY task_id) sc " +
            "ON sc.task_id = t.id "

    fun getTasks(view: String): List<WidgetTask> {
        val db = getReadDb()
        val (whereOrderClause, args) = when {
            view == "inbox" ->
                "WHERE t.is_deleted = 0 AND t.is_completed = 0 AND (t.project_id = 'default' OR t.due_date IS NOT NULL) ORDER BY CASE WHEN t.due_date IS NULL THEN 1 ELSE 0 END, t.due_date" to emptyArray()
            view == "timeline" ->
                "WHERE t.due_date IS NOT NULL AND t.is_deleted = 0 AND t.is_completed = 0 ORDER BY t.due_date" to emptyArray()
            view.startsWith("project:") ->
                "WHERE t.project_id = ? AND t.is_deleted = 0 AND t.is_completed = 0 ORDER BY CASE WHEN t.due_date IS NULL THEN 1 ELSE 0 END, t.due_date" to arrayOf(view.removePrefix("project:"))
            else ->
                "WHERE t.is_deleted = 0 AND t.is_completed = 0 AND (t.project_id = 'default' OR t.due_date IS NOT NULL) ORDER BY CASE WHEN t.due_date IS NULL THEN 1 ELSE 0 END, t.due_date" to emptyArray()
        }
        val cursor = db.rawQuery(taskSelectWithSubtasks + whereOrderClause, args)
        val tasks = mutableListOf<WidgetTask>()
        while (cursor.moveToNext()) {
            tasks.add(
                WidgetTask(
                    id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
                    title = cursor.getString(cursor.getColumnIndexOrThrow("title")),
                    dueDate = if (cursor.isNull(cursor.getColumnIndexOrThrow("due_date"))) null else cursor.getLong(cursor.getColumnIndexOrThrow("due_date")),
                    priority = cursor.getInt(cursor.getColumnIndexOrThrow("priority")),
                    isCompleted = cursor.getInt(cursor.getColumnIndexOrThrow("is_completed")) == 1,
                    projectId = cursor.getString(cursor.getColumnIndexOrThrow("project_id")),
                    subtaskTotal = cursor.getInt(cursor.getColumnIndexOrThrow("subtask_total")),
                    subtaskCompleted = cursor.getInt(cursor.getColumnIndexOrThrow("subtask_completed")),
                )
            )
        }
        cursor.close()
        return tasks
    }

    fun getProjects(): List<WidgetProject> {
        val db = getReadDb()
        val cursor = db.rawQuery("SELECT id, name, color_index FROM projects WHERE is_deleted = 0 ORDER BY name", null)
        val projects = mutableListOf<WidgetProject>()
        while (cursor.moveToNext()) {
            projects.add(
                WidgetProject(
                    id = cursor.getString(cursor.getColumnIndexOrThrow("id")),
                    name = cursor.getString(cursor.getColumnIndexOrThrow("name")),
                    colorIndex = cursor.getInt(cursor.getColumnIndexOrThrow("color_index")),
                )
            )
        }
        cursor.close()
        return projects
    }

    fun toggleTask(taskId: String) {
        try {
            val db = getWriteDb()
            db.execSQL(
                "UPDATE tasks SET is_completed = CASE WHEN is_completed = 0 THEN 1 ELSE 0 END, updated_at = ? WHERE id = ?",
                arrayOf<Any>(System.currentTimeMillis(), taskId)
            )
        } catch (e: Exception) {
            Log.e(TAG, "toggleTask failed for $taskId", e)
        }
    }

    fun close() {
        try { readDb?.close() } catch (_: Exception) {}
        try { writeDb?.close() } catch (_: Exception) {}
        readDb = null
        writeDb = null
    }
}
