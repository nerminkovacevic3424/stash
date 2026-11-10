package com.example.stash

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives ACTION_SEND text/plain from Instagram, TikTok, etc. and shows the
 * Flutter share sheet (`shareMain` in lib/main.dart) in a transparent window
 * over the sharing app.
 */
class ShareActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stash/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> result.success(sharedText())
                "close" -> {
                    result.success(null)
                    finish()
                    @Suppress("DEPRECATION")
                    overridePendingTransition(0, 0)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Instagram and TikTok put the link in EXTRA_TEXT, sometimes with a blurb
    // around it; the Dart side extracts the URL.
    private fun sharedText(): String? {
        val i = intent ?: return null
        if (i.action != Intent.ACTION_SEND) return null
        return listOfNotNull(i.getStringExtra(Intent.EXTRA_TEXT), i.getStringExtra(Intent.EXTRA_SUBJECT))
            .joinToString("\n")
            .ifBlank { null }
    }
}
