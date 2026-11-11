package com.example.stash

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openFromWidget(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openFromWidget(intent)
    }

    override fun onStop() {
        super.onStop()
        // Whatever changed while the app was open should show on the widget.
        StashWidgetProvider.refreshAll(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stash/open").setMethodCallHandler { call, result ->
            when (call.method) {
                "openInApp" -> {
                    val url = call.argument<String>("url")
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(url != null && openInApp(this, url, packages))
                }
                "shareText" -> {
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                    startActivity(Intent.createChooser(send, call.argument<String>("title")))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The home screen widget opens its post through this activity. */
    private fun openFromWidget(intent: Intent?) {
        val url = intent?.getStringExtra(EXTRA_OPEN_URL) ?: return
        intent.removeExtra(EXTRA_OPEN_URL) // do not reopen it on rotation
        val packages = APPS[intent.getStringExtra(EXTRA_OPEN_PLATFORM)] ?: emptyList()
        if (!openInApp(this, url, packages)) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: ActivityNotFoundException) {
            }
        }
    }

    companion object {
        const val EXTRA_OPEN_URL = "stash_open_url"
        const val EXTRA_OPEN_PLATFORM = "stash_open_platform"

        /** Packages that play each platform's links (same list as post_card.dart). */
        val APPS = mapOf(
            "tiktok" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill", "com.zhiliaoapp.musically.go"),
            "instagram" to listOf("com.instagram.android", "com.instagram.lite"),
            "youtube" to listOf("com.google.android.youtube"),
            "facebook" to listOf("com.facebook.katana", "com.facebook.lite"),
            "x" to listOf("com.twitter.android"),
        )

        /**
         * Hands the link straight to the platform's own app. A plain VIEW intent
         * lets Android pick, and it often picks the browser even when the app is
         * installed, which shows the post as a web page instead of in the app.
         */
        fun openInApp(context: Context, url: String, packages: List<String>): Boolean {
            for (pkg in packages) {
                try {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            .setPackage(pkg)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    return true
                } catch (_: ActivityNotFoundException) {
                    // Not installed, or it does not take this link; try the next one.
                } catch (_: SecurityException) {
                }
            }
            return false
        }
    }
}
