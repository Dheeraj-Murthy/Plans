package com.plansapp.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import com.plansapp.R
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

private const val PREFS_NAME = "HomeWidgetPreferences"
private const val TAG = "PlansWidget"
private const val REFRESH_INTERVAL_MS = 30 * 60 * 1000L

class PlansAppWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = buildWidgetViews(context, widgetData, widgetId)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
        scheduleRefreshAlarm(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        cancelRefreshAlarm(context)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleRefreshAlarm(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelRefreshAlarm(context)
    }

    companion object {
        private const val REFRESH_REQUEST_CODE = 999999
        private const val OVERDUE_COLOR = 0xFFE53935.toInt()

        fun scheduleRefreshAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                    action = ACTION_REFRESH
                }
                val pi = PendingIntent.getBroadcast(
                    context, REFRESH_REQUEST_CODE, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
                alarmManager.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME,
                    SystemClock.elapsedRealtime() + REFRESH_INTERVAL_MS,
                    REFRESH_INTERVAL_MS,
                    pi,
                )
            } catch (e: Exception) {
                Log.e(TAG, "scheduleRefreshAlarm failed", e)
            }
        }

        fun cancelRefreshAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                    action = ACTION_REFRESH
                }
                val pi = PendingIntent.getBroadcast(
                    context, REFRESH_REQUEST_CODE, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
                )
                if (pi != null) {
                    alarmManager.cancel(pi)
                    pi.cancel()
                }
            } catch (e: Exception) {
                Log.e(TAG, "cancelRefreshAlarm failed", e)
            }
        }

        private fun hapticFeedback(context: Context) {
            try {
                val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (vibrator.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        vibrator.vibrate(30)
                    }
                }
            } catch (_: Exception) {}
        }
        private const val ACTION_TOGGLE = "com.plansapp.action.TOGGLE"
        private const val ACTION_SET_VIEW = "com.plansapp.action.SET_VIEW"
        private const val ACTION_REFRESH = "com.plansapp.action.REFRESH"
        private const val ACTION_WIDGET_CLICK = "com.plansapp.action.WIDGET_CLICK"
        private const val EXTRA_TASK_ID = "task_id"
        private const val EXTRA_VIEW = "view"
        private const val EXTRA_APP_WIDGET_ID = "appWidgetId"

        private const val VIEW_PICKER = "picker"
        private const val VIEW_INBOX = "inbox"
        private const val VIEW_TODAY = "today"
        private const val VIEW_COMPLETED = "completed"
        private const val VIEW_PROJECT_PREFIX = "project:"

        private const val MAX_VISIBLE_OPTIONS = 6

        fun buildWidgetViews(
            context: Context,
            widgetData: SharedPreferences,
            widgetId: Int,
        ): RemoteViews {
            val view = widgetData.getString("widget_view_$widgetId", VIEW_INBOX) ?: VIEW_INBOX
            return try {
                if (view == VIEW_PICKER) {
                    buildViewPickerViews(context, widgetData, widgetId)
                } else {
                    buildTaskListViews(context, widgetData, widgetId, view)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to build widget views, showing empty", e)
                RemoteViews(context.packageName, R.layout.widget_task_list).apply {
                    setTextViewText(R.id.tv_header_title, getViewDisplayName(widgetData, view))
                }
            }
        }

        private fun buildTaskListViews(
            context: Context,
            widgetData: SharedPreferences,
            widgetId: Int,
            view: String,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_task_list)

            val tasksJson = widgetData.getString("widget_tasks_$view", "[]") ?: "[]"
            val raw = JSONArray(tasksJson)
            val tasks = JSONArray()
            for (i in 0 until raw.length()) {
                val el = raw.opt(i)
                if (el is JSONObject) {
                    tasks.put(el)
                } else if (el is String) {
                    try { tasks.put(JSONObject(el)) } catch (_: Exception) {}
                }
            }
            val taskCount = tasks.length()

            val selectedName = getViewDisplayName(widgetData, view)
            val headerText = if (taskCount > 0) "$selectedName ($taskCount)" else selectedName
            views.setTextViewText(R.id.tv_header_title, headerText)
            views.setContentDescription(R.id.tv_header_title, "$selectedName — tap to switch view")

            val headerIntent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                action = ACTION_SET_VIEW
                putExtra(EXTRA_VIEW, VIEW_PICKER)
                putExtra(EXTRA_APP_WIDGET_ID, widgetId)
            }
            val headerPi = PendingIntent.getBroadcast(
                context, widgetId, headerIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.tv_header_title, headerPi)
            views.setOnClickPendingIntent(R.id.iv_header_dot, headerPi)

            val rootIntent = Intent(context, com.plansapp.MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
            }
            val rootPi = PendingIntent.getActivity(
                context, widgetId * 100, rootIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.ll_root, rootPi)

            val addIntent = Intent(context, com.plansapp.MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                putExtra("action", "add_task")
            }
            val addPi = PendingIntent.getActivity(
                context, widgetId * 100 + 1, addIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.btn_add, addPi)
            views.setContentDescription(R.id.btn_add, "Add task")

            if (taskCount == 0) {
                views.setViewVisibility(R.id.tv_empty, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.task_list, android.view.View.GONE)
                return views
            }
            views.setViewVisibility(R.id.tv_empty, android.view.View.GONE)
            views.setViewVisibility(R.id.task_list, android.view.View.VISIBLE)

            val serviceIntent = Intent(context, TaskRemoteViewsService::class.java).apply {
                putExtra(EXTRA_VIEW, view)
                putExtra(EXTRA_APP_WIDGET_ID, widgetId)
            }

            val templateIntent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                action = ACTION_WIDGET_CLICK
            }
            val templatePi = PendingIntent.getBroadcast(
                context, widgetId + 1000, templateIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )

            views.setRemoteAdapter(R.id.task_list, serviceIntent)
            views.setPendingIntentTemplate(R.id.task_list, templatePi)

            return views
        }

        private fun buildViewPickerViews(
            context: Context,
            widgetData: SharedPreferences,
            widgetId: Int,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_view_picker)

            class BuiltInView(val name: String, val viewKey: String, val textId: Int, val dotId: Int, val rowId: Int, val dotRes: Int)
            val builtInViews = listOf(
                BuiltInView("Inbox", VIEW_INBOX, R.id.tv_option_1, R.id.iv_dot_1, R.id.ll_option_1, R.drawable.widget_dot_purple),
                BuiltInView("Today", VIEW_TODAY, R.id.tv_option_2, R.id.iv_dot_2, R.id.ll_option_2, R.drawable.widget_dot_green),
                BuiltInView("Completed", VIEW_COMPLETED, R.id.tv_option_3, R.id.iv_dot_3, R.id.ll_option_3, R.drawable.widget_dot_orange),
            )

            for (b in builtInViews) {
                val name = b.name
                val viewKey = b.viewKey
                val textId = b.textId
                val dotId = b.dotId
                val rowId = b.rowId
                val dotRes = b.dotRes
                views.setTextViewText(textId, name)
                views.setViewVisibility(rowId, android.view.View.VISIBLE)
                views.setImageViewResource(dotId, dotRes)
                views.setContentDescription(textId, name)
                val intent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                    action = ACTION_SET_VIEW
                    putExtra(EXTRA_VIEW, viewKey)
                    putExtra(EXTRA_APP_WIDGET_ID, widgetId)
                }
                val pi = PendingIntent.getBroadcast(
                    context, viewKey.hashCode() + widgetId, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(textId, pi)
            }

            val projectsJson = widgetData.getString("widget_projects", "[]") ?: "[]"
            val projects = JSONArray(projectsJson)
            val maxProjects = MAX_VISIBLE_OPTIONS - builtInViews.size
            val projectCount = minOf(projects.length(), maxProjects)

            if (projectCount > 0) {
                views.setViewVisibility(R.id.divider, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.divider, android.view.View.GONE)
            }

            for (i in 0 until projectCount) {
                val slotIdx = builtInViews.size + i + 1
                val rowId = context.resources.getIdentifier("ll_option_$slotIdx", "id", context.packageName)
                val textId = context.resources.getIdentifier("tv_option_$slotIdx", "id", context.packageName)
                val dotId = context.resources.getIdentifier("iv_dot_$slotIdx", "id", context.packageName)
                if (rowId == 0 || textId == 0 || dotId == 0) {
                    Log.w(TAG, "Resource ID not found for option slot $slotIdx")
                    continue
                }
                val projectObj = projects.optJSONObject(i) ?: continue
                val projectName = projectObj.getString("name")
                val projectId = projectObj.getString("id")
                val colorIndex = projectObj.optInt("color_index", 0)

                views.setTextViewText(textId, projectName)
                views.setViewVisibility(rowId, android.view.View.VISIBLE)
                views.setImageViewResource(dotId, dotResForColorIndex(colorIndex))
                views.setContentDescription(textId, "$projectName — project")
                val intent = Intent(context, WidgetInteractionReceiver::class.java).apply {
                    action = ACTION_SET_VIEW
                    putExtra(EXTRA_VIEW, "${VIEW_PROJECT_PREFIX}$projectId")
                    putExtra(EXTRA_APP_WIDGET_ID, widgetId)
                }
                val pi = PendingIntent.getBroadcast(
                    context, projectId.hashCode() + widgetId, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(textId, pi)
            }

            for (i in (builtInViews.size + projectCount + 1)..MAX_VISIBLE_OPTIONS) {
                val rowId = context.resources.getIdentifier("ll_option_$i", "id", context.packageName)
                if (rowId != 0) views.setViewVisibility(rowId, android.view.View.GONE)
            }

            return views
        }

        private data class ProjectInfo(val name: String, val colorIndex: Int)

        private fun lookupProjectInfo(widgetData: SharedPreferences, projectId: String): ProjectInfo? {
            if (projectId == "default" || projectId.isEmpty()) return ProjectInfo("Inbox", 0)
            val projectsJson = widgetData.getString("widget_projects", "[]") ?: "[]"
            val projects = JSONArray(projectsJson)
            for (i in 0 until projects.length()) {
                val p = projects.optJSONObject(i) ?: continue
                if (p.optString("id", "") == projectId) {
                    return ProjectInfo(p.getString("name"), p.optInt("color_index", 0))
                }
            }
            return null
        }

        private fun lookupProjectName(widgetData: SharedPreferences, projectId: String): String? {
            return lookupProjectInfo(widgetData, projectId)?.name
        }

        private fun getViewDisplayName(widgetData: SharedPreferences, view: String): String {
            return when (view) {
                VIEW_INBOX -> "Inbox"
                VIEW_TODAY -> "Today"
                VIEW_COMPLETED -> "Completed"
                VIEW_PICKER -> ""
                else -> {
                    if (view.startsWith(VIEW_PROJECT_PREFIX)) {
                        val projectId = view.removePrefix(VIEW_PROJECT_PREFIX)
                        lookupProjectName(widgetData, projectId) ?: "Inbox"
                    } else "Inbox"
                }
            }
        }

        private fun dotResForColorIndex(index: Int): Int {
            return when (index % 5) {
                0 -> R.drawable.widget_dot_purple
                1 -> R.drawable.widget_dot_red
                2 -> R.drawable.widget_dot_green
                3 -> R.drawable.widget_dot_orange
                else -> R.drawable.widget_dot_blue
            }
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

        fun handleToggle(
            context: Context,
            appWidgetId: Int,
            taskId: String,
        ) {
            Log.d(TAG, "handleToggle appWidgetId=$appWidgetId taskId=$taskId")
            hapticFeedback(context)
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val view = prefs.getString("widget_view_$appWidgetId", VIEW_INBOX) ?: VIEW_INBOX
                val tasksJson = prefs.getString("widget_tasks_$view", "[]") ?: "[]"
                val tasks = JSONArray(tasksJson)

                for (i in 0 until tasks.length()) {
                    val obj = tasks.optJSONObject(i) ?: continue
                    if (obj.getString("id") == taskId) {
                        obj.put("is_completed", !obj.optBoolean("is_completed", false))
                        break
                    }
                }

                prefs.edit().putString("widget_tasks_$view", tasks.toString()).apply()
            } catch (e: Exception) {
                Log.e(TAG, "handleToggle failed", e)
            }

            try {
                val togglePrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val existing = togglePrefs.getString("pending_toggle_ids", "[]") ?: "[]"
                val arr = JSONArray(existing)
                arr.put(taskId)
                togglePrefs.edit().putString("pending_toggle_ids", arr.toString()).apply()
            } catch (_: Exception) {}

            try {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.task_list)
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val views = buildWidgetViews(context, prefs, appWidgetId)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "handleToggle widget update failed", e)
            }
        }

        fun handleSetView(
            context: Context,
            appWidgetId: Int,
            view: String,
        ) {
            hapticFeedback(context)
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                prefs.edit().putString("widget_view_$appWidgetId", view).apply()

                val appWidgetManager = AppWidgetManager.getInstance(context)
                val views = if (view == VIEW_PICKER) {
                    buildViewPickerViews(context, prefs, appWidgetId)
                } else {
                    buildTaskListViews(context, prefs, appWidgetId, view)
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "handleSetView failed", e)
            }
        }

        fun handleRefresh(context: Context, appWidgetIds: IntArray) {
            try {
                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val db = WidgetDbHelper.getInstance(context)

                val allProjects = db.getProjects()
                prefs.edit().putString("widget_projects", JSONArray(allProjects.map { p ->
                    JSONObject().apply {
                        put("id", p.id)
                        put("name", p.name)
                        put("color_index", p.colorIndex)
                    }
                }).toString()).apply()

                for (widgetId in appWidgetIds) {
                    val view = prefs.getString("widget_view_$widgetId", VIEW_INBOX) ?: VIEW_INBOX
                    if (view != VIEW_PICKER) {
                        val tasks = db.getTasks(view)
                        prefs.edit().putString("widget_tasks_$view", JSONArray(tasks.map { t ->
                            JSONObject().apply {
                                put("id", t.id)
                                put("title", t.title)
                                put("due_date", t.dueDate ?: JSONObject.NULL)
                                put("priority", t.priority)
                                put("is_completed", t.isCompleted)
                                put("project_id", t.projectId)
                            }
                        }).toString()).apply()
                    }
                    val views = buildWidgetViews(context, prefs, widgetId)
                    appWidgetManager.updateAppWidget(widgetId, views)
                }
            } catch (e: Exception) {
                Log.e(TAG, "handleRefresh failed", e)
            }
        }
    }
}
