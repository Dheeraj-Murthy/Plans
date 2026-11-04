package com.plansapp.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.plansapp.MainActivity
import com.plansapp.QuickAddTransactionActivity
import com.plansapp.R
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen "big balance + two buttons" widget. Unlike [PlansAppWidgetProvider]
 * this has no native SQLite reads or periodic refresh alarm — the balance only
 * ever changes through a transaction submitted via the app itself (never by
 * another process acting on the DB directly, unlike task completion), so the
 * app pushing fresh data via WidgetBridge.notifyBudgetUpdate() right after
 * every mutation is enough to keep this current.
 */
class PlansBudgetWidgetProvider : HomeWidgetProvider() {

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
    }

    companion object {
        private fun buildWidgetViews(
            context: Context,
            widgetData: SharedPreferences,
            widgetId: Int,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_budget)

            val currencySymbol = widgetData.getString("widget_budget_currency", "₹") ?: "₹"
            val balance = widgetData.getString("widget_budget_balance", "0.00")?.toDoubleOrNull() ?: 0.0
            val isOver = balance < 0
            val formatted = formatAmount(kotlin.math.abs(balance))

            views.setTextViewText(R.id.tv_balance, "$currencySymbol$formatted")
            views.setTextColor(R.id.tv_balance, if (isOver) 0xFFF87171.toInt() else 0xFF4ADE80.toInt())
            views.setTextViewText(R.id.tv_balance_caption, if (isOver) "over" else "left")

            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                putExtra("action", "open_budget")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPi = PendingIntent.getActivity(
                context,
                widgetId * 100,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.iv_header_dot, openPi)
            views.setOnClickPendingIntent(R.id.tv_header_title, openPi)
            views.setOnClickPendingIntent(R.id.ll_root, openPi)

            views.setOnClickPendingIntent(
                R.id.btn_expense,
                quickAddPendingIntent(context, widgetId * 100 + 1, "expense"),
            )
            views.setOnClickPendingIntent(
                R.id.btn_money,
                quickAddPendingIntent(context, widgetId * 100 + 2, "topup"),
            )

            return views
        }

        private fun quickAddPendingIntent(context: Context, requestCode: Int, type: String): PendingIntent {
            val intent = Intent(context, QuickAddTransactionActivity::class.java).apply {
                putExtra("transaction_type", type)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        // Thousands-grouped, 2dp — mirrors lib/shared/helpers/currency.dart's
        // formatCurrency exactly so the widget and the app never disagree.
        private fun formatAmount(amount: Double): String {
            val fixed = String.format(java.util.Locale.US, "%.2f", amount)
            val parts = fixed.split(".")
            val whole = parts[0]
            val decimals = parts[1]
            val grouped = StringBuilder()
            for (i in whole.indices) {
                if (i > 0 && (whole.length - i) % 3 == 0) grouped.append(',')
                grouped.append(whole[i])
            }
            return "$grouped.$decimals"
        }
    }
}
