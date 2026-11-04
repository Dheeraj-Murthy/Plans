package com.plansapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Minimal translucent host for the Budget widget's "+ Expense"/"+ Money"
 * buttons — mirrors QuickAddActivity exactly, one Dart entrypoint branch
 * (see main.dart) shows just the add-transaction composer as a bottom sheet
 * over the live homescreen, then finishes this activity.
 */
class QuickAddTransactionActivity : FlutterActivity() {
    private val DEEPLINK_CHANNEL = "plans/widget/deeplink"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val transactionType = intent.getStringExtra("transaction_type") ?: "expense"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEPLINK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialIntent" -> result.success(
                        mapOf("action" to "quick_add_transaction", "transaction_type" to transactionType),
                    )
                    "checkPendingWidgetSync" -> result.success(emptyList<String>())
                    else -> result.notImplemented()
                }
            }
    }
}
