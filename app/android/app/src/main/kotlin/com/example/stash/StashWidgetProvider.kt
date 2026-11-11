package com.example.stash

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.view.View
import android.widget.RemoteViews
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Home screen widget: one saved post you have not watched yet, picked at
 * random each time it refreshes. Tapping it opens the post in its own app.
 *
 * It reads the app's SQLite file directly (the schema lives in
 * lib/data/repo.dart) and never writes to it.
 */
class StashWidgetProvider : AppWidgetProvider() {
    private data class Pick(
        val url: String,
        val platform: String,
        val text: String?,
        val author: String?,
        val folder: String?,
        val image: String?,
    )

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Reading the database and fetching the cover must not block the main thread.
        val pending = goAsync()
        thread {
            try {
                val pick = pick(context)
                val cover = pick?.image?.let(::loadCover)
                for (id in ids) manager.updateAppWidget(id, render(context, id, pick, cover))
            } catch (_: Throwable) {
                // A widget must never crash the host; it keeps its last content instead.
            } finally {
                pending.finish()
            }
        }
    }

    private fun pick(context: Context): Pick? {
        val file = context.getDatabasePath("stash.db")
        if (!file.exists()) return null
        val db = SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        try {
            db.rawQuery(
                """SELECT p.url, p.platform, COALESCE(p.ai_description, p.caption), p.author, f.name, p.thumbnail_url
                   FROM posts p LEFT JOIN folders f ON f.id = p.folder_id
                   WHERE p.deleted = 0 ORDER BY p.watched ASC, RANDOM() LIMIT 1""",
                null,
            ).use { c ->
                if (!c.moveToFirst()) return null
                return Pick(c.getString(0), c.getString(1), c.getString(2), c.getString(3), c.getString(4), c.getString(5))
            }
        } finally {
            db.close()
        }
    }

    private fun render(context: Context, widgetId: Int, pick: Pick?, cover: Bitmap?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.stash_widget)
        val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (pick == null) {
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_empty))
            views.setTextViewText(R.id.widget_sub, "")
            views.setViewVisibility(R.id.widget_image, View.GONE)
        } else {
            val text = pick.text?.replace(Regex("\\s+"), " ")?.trim().orEmpty()
            views.setTextViewText(R.id.widget_title, text.ifEmpty { pick.url })
            views.setTextViewText(
                R.id.widget_sub,
                listOfNotNull(pick.author?.let { "@$it" }, pick.folder).joinToString("  ·  "),
            )
            if (cover != null) {
                views.setImageViewBitmap(R.id.widget_image, cover)
                views.setViewVisibility(R.id.widget_image, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_image, View.GONE)
            }
            open.putExtra(MainActivity.EXTRA_OPEN_URL, pick.url)
            open.putExtra(MainActivity.EXTRA_OPEN_PLATFORM, pick.platform)
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context,
                widgetId,
                open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return views
    }

    /** Downloads the cover, scaled down and with rounded corners; null on any problem. */
    private fun loadCover(address: String): Bitmap? = try {
        val connection = (URL(address).openConnection() as HttpURLConnection).apply {
            connectTimeout = 4000
            readTimeout = 4000
        }
        val bytes = connection.inputStream.use { it.readBytes() }
        connection.disconnect()
        if (bytes.size > 4 * 1024 * 1024) {
            null
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / sample > 480 || bounds.outHeight / sample > 600) sample *= 2
            val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            raw?.let(::rounded)
        }
    } catch (_: Throwable) {
        null
    }

    /** Centre-crops to 4:5 and rounds the corners. */
    private fun rounded(source: Bitmap): Bitmap {
        val width = minOf(source.width, source.height * 4 / 5)
        val height = minOf(source.height, width * 5 / 4)
        val cropped = Bitmap.createBitmap(source, (source.width - width) / 2, (source.height - height) / 2, width, height)
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(cropped, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val radius = width * 0.14f
        Canvas(out).drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)
        return out
    }

    companion object {
        /** Asks every placed widget to pick again. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, StashWidgetProvider::class.java))
            if (ids.isEmpty()) return
            context.sendBroadcast(
                Intent(context, StashWidgetProvider::class.java)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            )
        }
    }
}
