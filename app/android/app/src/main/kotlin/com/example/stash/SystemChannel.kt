package com.example.stash

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Small system helpers shared by the main app and the share sheet. */
object SystemChannel {
    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "stash/system").setMethodCallHandler { call, result ->
            if (call.method == "openNotificationSettings") {
                result.success(openNotificationSettings(activity))
            } else {
                result.notImplemented()
            }
        }
    }

    /** Opens this app's notification settings; the app's general settings page if that fails. */
    private fun openNotificationSettings(activity: Activity): Boolean {
        val direct = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        val general = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
        for (intent in listOf(direct, general)) {
            try {
                activity.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
