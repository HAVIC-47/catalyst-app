package com.havic47.catalyst

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Home-screen widget: today's spending, and a + that opens the app on a new
// entry. The app sends the figures (already written in its language and
// currency) whenever its entries change; until it's opened on a new day the
// widget shows a dash rather than yesterday's total.
class CatalystWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context)) }
    }

    companion object {
        const val ACTION_ADD = "com.havic47.catalyst.ADD"
        private const val PREFS = "catalyst_widget"

        private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

        /** Store what the app sent and redraw every placed widget. */
        fun save(context: Context, data: Map<*, *>) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                for (key in listOf("date", "label", "amount", "sub", "stale", "add")) {
                    (data[key] as? String)?.let { putString(key, it) }
                }
                apply()
            }
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CatalystWidget::class.java))
            ids.forEach { manager.updateAppWidget(it, views(context)) }
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val fresh = prefs.getString("date", null) == today()
            return RemoteViews(context.packageName, R.layout.catalyst_widget).apply {
                setTextViewText(R.id.widget_label, prefs.getString("label", null) ?: "Spent today")
                setTextViewText(R.id.widget_amount, if (fresh) prefs.getString("amount", null) ?: "—" else "—")
                setTextViewText(
                    R.id.widget_sub,
                    if (fresh) prefs.getString("sub", null) ?: "" else prefs.getString("stale", null) ?: "Open Catalyst to update",
                )
                setContentDescription(R.id.widget_add, prefs.getString("add", null) ?: "New entry")
                setOnClickPendingIntent(R.id.widget_root, launch(context, null, 0))
                setOnClickPendingIntent(R.id.widget_add, launch(context, ACTION_ADD, 1))
            }
        }

        private fun launch(context: Context, action: String?, code: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action ?: Intent.ACTION_MAIN
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}
