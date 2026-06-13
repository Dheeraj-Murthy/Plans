package com.plansapp.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Paint
import android.util.Log
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.plansapp.R
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

private const val PREFS_NAME = "HomeWidgetPreferences"
private const val TAG = "PlansWidget"
private const val OVERDUE_COLOR = 0xFFE53935.toInt()

private const val VIEW_INBOX = "inbox"
private const val VIEW_TODAY = "today"
private const val VIEW_COMPLETED = "completed"
private const val VIEW_PROJECT_PREFIX = "project:"
private const val EXTRA_VIEW = "view"
private const val EXTRA_TASK_ID = "task_id"
private const val EXTRA_APP_WIDGET_ID = "appWidgetId"

class TaskRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var tasks = JSONArray()

    private val widgetId: Int
        get() = intent.getIntExtra(EXTRA_APP_WIDGET_ID, -1)
            .takeIf { it != -1 }
            ?: intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )

    override fun onCreate() {}

    override fun onDestroy() {}

    override fun onDataSetChanged() {
        val view = intent.getStringExtra(EXTRA_VIEW)
            ?: prefs.getString("widget_view_$widgetId", VIEW_INBOX) ?: VIEW_INBOX
        val tasksJson = prefs.getString("widget_tasks_$view", "[]") ?: "[]"
        tasks = try {
            val raw = JSONArray(tasksJson)
            val cleaned = JSONArray()
            for (i in 0 until raw.length()) {
                val el = raw.opt(i)
                if (el is JSONObject) cleaned.put(el)
                else if (el is String) {
                    try {
                        cleaned.put(JSONObject(el))
                    } catch (_: Exception) {}
                }
            }
            cleaned
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse tasks", e)
            JSONArray()
        }
    }

    override fun getCount(): Int = tasks.length()

    override fun getViewAt(position: Int): RemoteViews {
        val item = tasks.optJSONObject(position)
            ?: return RemoteViews(context.packageName, R.layout.widget_task_item)

        val taskId = item.optString("id", "")
        val title = item.optString("title", "")
        val isCompleted = item.optBoolean("is_completed", false)
        val priority = item.optInt("priority", 1)
        val dueDate = if (item.has("due_date") && !item.isNull("due_date")) {
            item.optLong("due_date", -1)
        } else -1L

        val rv = RemoteViews(context.packageName, R.layout.widget_task_item)

        val checkRes = if (isCompleted) R.drawable.widget_checkbox_checked
        else when (priority) {
            4 -> R.drawable.widget_checkbox_border_critical
            3 -> R.drawable.widget_checkbox_border_red
            2 -> R.drawable.widget_checkbox_border_yellow
            else -> R.drawable.widget_checkbox_border_gray
        }
        rv.setImageViewResource(R.id.iv_check, checkRes)
        rv.setContentDescription(
            R.id.iv_check,
            "${if (isCompleted) "Completed" else "Incomplete"}, $title",
        )

        rv.setTextViewText(R.id.tv_title, title)
        if (isCompleted) {
            rv.setInt(R.id.tv_title, "setPaintFlags", Paint.STRIKE_THRU_TEXT_FLAG)
            rv.setTextColor(R.id.tv_title, 0xFF888888.toInt())
        } else {
            rv.setInt(R.id.tv_title, "setPaintFlags", 0)
            val titleColor = when (priority) {
                4 -> 0xFFFF1744.toInt()
                3 -> 0xFFFF6B6B.toInt()
                2 -> 0xFFE8943A.toInt()
                else -> 0xFFE0E0E0.toInt()
            }
            rv.setTextColor(R.id.tv_title, titleColor)
        }
        rv.setContentDescription(R.id.tv_title, "$title, tap to open")

        val now = System.currentTimeMillis()
        val isOverdue = dueDate > 0 && dueDate < now && !isCompleted

        if (dueDate > 0) {
            val dateLabel = formatDueDate(dueDate)
            val timeStr = if (_hasTime(dueDate)) formatTime(dueDate) else null
            val dueText = if (timeStr != null) "$dateLabel $timeStr" else dateLabel
            rv.setTextViewText(R.id.tv_due, dueText)
            rv.setViewVisibility(R.id.tv_due, android.view.View.VISIBLE)
            rv.setInt(R.id.tv_due, "setBackgroundResource", R.drawable.widget_pill_bg)
            rv.setTextColor(R.id.tv_due, if (isOverdue) OVERDUE_COLOR else 0xFF888888.toInt())
            rv.setContentDescription(R.id.tv_due, "Due $dueText")
        } else {
            rv.setViewVisibility(R.id.tv_due, android.view.View.GONE)
        }

        val projectInfo = lookupProjectInfo(
            prefs, item.optString("project_id", ""),
        )
        if (projectInfo != null) {
            val locationColor = colorForProjectIndex(projectInfo.colorIndex)
            rv.setTextViewText(R.id.tv_location, projectInfo.name)
            rv.setTextColor(R.id.tv_location, locationColor)
            rv.setViewVisibility(R.id.tv_location, android.view.View.VISIBLE)
            rv.setContentDescription(R.id.tv_location, projectInfo.name)
        } else {
            rv.setViewVisibility(R.id.tv_location, android.view.View.GONE)
        }

        val toggleFill = Intent().apply {
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_APP_WIDGET_ID, widgetId)
            putExtra("click_type", "toggle")
        }
        rv.setOnClickFillInIntent(R.id.iv_check, toggleFill)
        rv.setOnClickFillInIntent(R.id.ll_item, toggleFill)

        val openFill = Intent().apply {
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra("click_type", "open")
        }
        rv.setOnClickFillInIntent(R.id.tv_title, openFill)

        return rv
    }

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    private data class ProjectInfo(val name: String, val colorIndex: Int)

    private fun lookupProjectInfo(
        widgetData: SharedPreferences,
        projectId: String,
    ): ProjectInfo? {
        if (projectId == "default" || projectId.isEmpty()) return ProjectInfo("Inbox", 0)
        val projectsJson = widgetData.getString("widget_projects", "[]") ?: "[]"
        val projects = JSONArray(projectsJson)
        for (i in 0 until projects.length()) {
            val p = projects.optJSONObject(i) ?: continue
            if (p.optString("id", "") == projectId) {
                return ProjectInfo(
                    p.getString("name"),
                    p.optInt("color_index", 0),
                )
            }
        }
        return null
    }

    private fun colorForProjectIndex(index: Int): Int {
        return when (index % 5) {
            0 -> 0xFF7C6DF2.toInt()
            1 -> 0xFFE45C5C.toInt()
            2 -> 0xFF3CAE7C.toInt()
            3 -> 0xFFE8943A.toInt()
            else -> 0xFF5E8AE4.toInt()
        }
    }

    private fun _hasTime(epochMillis: Long): Boolean {
        val cal = Calendar.getInstance().apply { timeInMillis = epochMillis }
        return cal.get(Calendar.HOUR_OF_DAY) != 0 || cal.get(Calendar.MINUTE) != 0
    }

    private fun formatTime(epochMillis: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = epochMillis }
        return SimpleDateFormat("h:mm a", Locale.getDefault()).format(cal.time)
    }

    private fun formatDueDate(epochMillis: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = epochMillis }
        val now = Calendar.getInstance()
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
        return when {
            cal.get(Calendar.DAY_OF_YEAR) == now.get(Calendar.DAY_OF_YEAR) &&
                cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) -> "Today"
            cal.get(Calendar.DAY_OF_YEAR) == tomorrow.get(Calendar.DAY_OF_YEAR) &&
                cal.get(Calendar.YEAR) == tomorrow.get(Calendar.YEAR) -> "Tomorrow"
            else -> SimpleDateFormat("MMM d", Locale.getDefault()).format(cal.time)
        }
    }
}