package com.plansapp.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

class WidgetInteractionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        when (action) {
            "com.plansapp.action.REFRESH" -> {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val cn = ComponentName(context, PlansAppWidgetProvider::class.java)
                val ids = appWidgetManager.getAppWidgetIds(cn)
                if (ids.isNotEmpty()) {
                    PlansAppWidgetProvider.handleRefresh(context, ids)
                }
            }
            "com.plansapp.action.TOGGLE" -> {
                val appWidgetId = intent.getIntExtra("appWidgetId", -1)
                val taskId = intent.getStringExtra("task_id") ?: return
                PlansAppWidgetProvider.handleToggle(context, appWidgetId, taskId)
            }
            "com.plansapp.action.SET_VIEW" -> {
                val appWidgetId = intent.getIntExtra("appWidgetId", -1)
                val view = intent.getStringExtra("view") ?: return
                PlansAppWidgetProvider.handleSetView(context, appWidgetId, view)
            }
            "com.plansapp.action.WIDGET_CLICK" -> {
                val clickType = intent.getStringExtra("click_type") ?: run {
                    android.util.Log.e("WidgetToggle", "click_type is null, action=${intent.action}")
                    return
                }
                when (clickType) {
                    "toggle" -> {
                        val appWidgetId = intent.getIntExtra("appWidgetId", -1)
                        val taskId = intent.getStringExtra("task_id") ?: run {
                            android.util.Log.e("WidgetToggle", "task_id is null, appWidgetId=$appWidgetId")
                            return
                        }
                        android.util.Log.d("WidgetToggle", "toggle appWidgetId=$appWidgetId taskId=$taskId")
                        PlansAppWidgetProvider.handleToggle(context, appWidgetId, taskId)
                    }
                    "open" -> {
                        val taskId = intent.getStringExtra("task_id") ?: return
                        val launchIntent = Intent(context, com.plansapp.MainActivity::class.java)
                        launchIntent.action = "es.antonborri.home_widget.action.LAUNCH"
                        launchIntent.putExtra("task_id", taskId)
                        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        context.startActivity(launchIntent)
                    }
                }
            }
        }
    }
}
