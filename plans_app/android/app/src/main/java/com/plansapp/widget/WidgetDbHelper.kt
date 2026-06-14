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

    fun getTasks(view: String): List<WidgetTask> {
        val db = getReadDb()
        val (query, args) = when {
            view == "inbox" ->
                "SELECT id, title, due_date, priority, is_completed, project_id FROM tasks WHERE is_deleted = 0 AND is_completed = 0 AND (project_id = 'default' OR due_date IS NOT NULL) ORDER BY CASE WHEN due_date IS NULL THEN 1 ELSE 0 END, due_date" to emptyArray()
            view == "timeline" ->
                "SELECT id, title, due_date, priority, is_completed, project_id FROM tasks WHERE due_date IS NOT NULL AND is_deleted = 0 AND is_completed = 0 ORDER BY due_date" to emptyArray()
            view.startsWith("project:") ->
                "SELECT id, title, due_date, priority, is_completed, project_id FROM tasks WHERE project_id = ? AND is_deleted = 0 AND is_completed = 0 ORDER BY CASE WHEN due_date IS NULL THEN 1 ELSE 0 END, due_date" to arrayOf(view.removePrefix("project:"))
            else ->
                "SELECT id, title, due_date, priority, is_completed, project_id FROM tasks WHERE is_deleted = 0 AND is_completed = 0 AND (project_id = 'default' OR due_date IS NOT NULL) ORDER BY CASE WHEN due_date IS NULL THEN 1 ELSE 0 END, due_date" to emptyArray()
        }
        val cursor = db.rawQuery(query, args)
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
