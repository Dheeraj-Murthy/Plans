package com.plansapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Minimal translucent host for the homescreen widget's "Add" button: a
 * single Dart entrypoint branch (see main.dart) shows just the task
 * composer as a bottom sheet over the live homescreen, then finishes this
 * activity — the full app/shell never gets created.
 */
class QuickAddActivity : FlutterActivity() {
    private val DEEPLINK_CHANNEL = "plans/widget/deeplink"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEEPLINK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialIntent" -> result.success(mapOf("action" to "quick_add"))
                    "checkPendingWidgetSync" -> result.success(emptyList<String>())
                    else -> result.notImplemented()
                }
            }
    }
}
