package com.example.stash

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stash/open").setMethodCallHandler { call, result ->
            if (call.method == "openInApp") {
                val url = call.argument<String>("url")
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                result.success(url != null && openInApp(url, packages))
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Hands the link straight to the platform's own app. A plain VIEW intent
     * lets Android pick, and it often picks the browser even when the app is
     * installed, which shows the post as a web page instead of in the app.
     */
    private fun openInApp(url: String, packages: List<String>): Boolean {
        for (pkg in packages) {
            try {
                startActivity(
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
