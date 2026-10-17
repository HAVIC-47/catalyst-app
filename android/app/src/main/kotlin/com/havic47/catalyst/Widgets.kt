package com.havic47.catalyst

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Home-screen widgets. The app sends every widget's figures in one map (already
// written in its language and currency) whenever its data changes; each widget
// draws its part. Figures tied to a day or a month show a dash once that day or
// month is over, until the app is opened again.
//
//   CatalystWidget  spent today, and a + for a new entry
//   MonthWidget     this month: spent, earned, saved
//   WalletsWidget   what's in each wallet, and the total
//   BillsWidget     the next bills due (overdue ones in red)
//   MoodWidget      five faces: tap one to log today's mood
object Widgets {
    const val ACTION_ADD = "com.havic47.catalyst.ADD"
    const val ACTION_OPEN = "com.havic47.catalyst.OPEN"
    const val ACTION_MOOD = "com.havic47.catalyst.MOOD"
    const val EXTRA_TARGET = "target"
    private const val PREFS = "catalyst_widget"
    private const val LATE = 0xFFD24B3A.toInt()

    private val kinds = listOf(
        CatalystWidget::class.java,
        MonthWidget::class.java,
        WalletsWidget::class.java,
        BillsWidget::class.java,
        MoodWidget::class.java,
    )

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    private fun thisMonth(): String = SimpleDateFormat("yyyy-MM", Locale.US).format(Date())
    private fun SharedPreferences.text(key: String, fallback: String = ""): String =
        getString(key, null)?.takeIf { it.isNotEmpty() } ?: fallback

    /** Store what the app sent and redraw every placed widget. */
    fun save(context: Context, data: Map<*, *>) {
        prefs(context).edit().apply {
            for ((key, value) in data) {
                if (key is String && value is String) putString(key, value)
            }
            apply()
        }
        val manager = AppWidgetManager.getInstance(context)
        for (kind in kinds) {
            val ids = manager.getAppWidgetIds(ComponentName(context, kind))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context, kind))
        }
    }

    fun views(context: Context, kind: Class<*>): RemoteViews = when (kind) {
        MonthWidget::class.java -> month(context)
        WalletsWidget::class.java -> wallets(context)
        BillsWidget::class.java -> bills(context)
        MoodWidget::class.java -> mood(context)
        else -> spentToday(context)
    }

    private fun spentToday(context: Context): RemoteViews {
        val p = prefs(context)
        val fresh = p.getString("date", null) == today()
        return RemoteViews(context.packageName, R.layout.catalyst_widget).apply {
            setTextViewText(R.id.widget_label, p.text("label", "Spent today"))
            setTextViewText(R.id.widget_amount, if (fresh) p.text("amount", "—") else "—")
            setTextViewText(R.id.widget_sub, if (fresh) p.text("sub") else p.text("stale", "Open Catalyst to update"))
            setContentDescription(R.id.widget_add, p.text("add", "New entry"))
            setOnClickPendingIntent(R.id.widget_root, launch(context, null, null, 0))
            setOnClickPendingIntent(R.id.widget_add, launch(context, ACTION_ADD, null, 1))
        }
    }

    private fun month(context: Context): RemoteViews {
        val p = prefs(context)
        val fresh = p.getString("m_month", null) == thisMonth()
        return RemoteViews(context.packageName, R.layout.widget_month).apply {
            setTextViewText(R.id.month_title, if (fresh) p.text("m_title", "This month") else p.text("stale", "Open Catalyst to update"))
            setTextViewText(R.id.month_spent_label, p.text("m_spent_l", "Spent"))
            setTextViewText(R.id.month_earned_label, p.text("m_earned_l", "Earned"))
            setTextViewText(R.id.month_saved_label, p.text("m_saved_l", "Saved"))
            setTextViewText(R.id.month_spent, if (fresh) p.text("m_spent", "—") else "—")
            setTextViewText(R.id.month_earned, if (fresh) p.text("m_earned", "—") else "—")
            setTextViewText(R.id.month_saved, if (fresh) p.text("m_saved", "—") else "—")
            if (fresh && p.getString("m_saved_neg", null) == "1") setTextColor(R.id.month_saved, LATE)
            setOnClickPendingIntent(R.id.month_root, launch(context, ACTION_OPEN, "dashboard", 20))
        }
    }

    private val walletRows = listOf(
        Triple(R.id.wallet_row_1, R.id.wallet_name_1, R.id.wallet_amount_1),
        Triple(R.id.wallet_row_2, R.id.wallet_name_2, R.id.wallet_amount_2),
        Triple(R.id.wallet_row_3, R.id.wallet_name_3, R.id.wallet_amount_3),
        Triple(R.id.wallet_row_4, R.id.wallet_name_4, R.id.wallet_amount_4),
    )

    private fun wallets(context: Context): RemoteViews {
        val p = prefs(context)
        return RemoteViews(context.packageName, R.layout.widget_wallets).apply {
            setTextViewText(R.id.wallets_title, p.text("w_title", "Wallets"))
            setTextViewText(R.id.wallets_total, p.text("w_total"))
            var shown = 0
            walletRows.forEachIndexed { i, (row, name, amount) ->
                val n = p.text("w${i + 1}_name")
                if (n.isEmpty()) {
                    setViewVisibility(row, View.GONE)
                } else {
                    shown++
                    setViewVisibility(row, View.VISIBLE)
                    setTextViewText(name, n)
                    setTextViewText(amount, p.text("w${i + 1}_amount"))
                    if (p.getString("w${i + 1}_neg", null) == "1") setTextColor(amount, LATE)
                }
            }
            setViewVisibility(R.id.wallets_empty, if (shown == 0) View.VISIBLE else View.GONE)
            setTextViewText(R.id.wallets_empty, p.text("w_empty", "Open Catalyst to see your wallets"))
            setOnClickPendingIntent(R.id.wallets_root, launch(context, ACTION_OPEN, "wallets", 21))
        }
    }

    private val billRows = listOf(
        listOf(R.id.bill_row_1, R.id.bill_name_1, R.id.bill_when_1, R.id.bill_amount_1),
        listOf(R.id.bill_row_2, R.id.bill_name_2, R.id.bill_when_2, R.id.bill_amount_2),
        listOf(R.id.bill_row_3, R.id.bill_name_3, R.id.bill_when_3, R.id.bill_amount_3),
    )

    private fun bills(context: Context): RemoteViews {
        val p = prefs(context)
        val day = today()
        return RemoteViews(context.packageName, R.layout.widget_bills).apply {
            setTextViewText(R.id.bills_title, p.text("b_title", "Bills due"))
            var shown = 0
            billRows.forEachIndexed { i, (row, name, due, amount) ->
                val n = p.text("b${i + 1}_name")
                if (n.isEmpty()) {
                    setViewVisibility(row, View.GONE)
                } else {
                    shown++
                    setViewVisibility(row, View.VISIBLE)
                    setTextViewText(name, n)
                    setTextViewText(due, p.text("b${i + 1}_when"))
                    setTextViewText(amount, p.text("b${i + 1}_amount"))
                    val dueOn = p.text("b${i + 1}_due")
                    if (dueOn.isNotEmpty() && dueOn < day) setTextColor(due, LATE)
                }
            }
            setViewVisibility(R.id.bills_empty, if (shown == 0) View.VISIBLE else View.GONE)
            setTextViewText(R.id.bills_empty, p.text("b_empty", "Nothing due — all paid."))
            setOnClickPendingIntent(R.id.bills_root, launch(context, ACTION_OPEN, "bills", 22))
        }
    }

    private val moodButtons = listOf(R.id.mood_1, R.id.mood_2, R.id.mood_3, R.id.mood_4, R.id.mood_5)
    private val moodNames = listOf("Awful", "Low", "Okay", "Good", "Great")

    private fun mood(context: Context): RemoteViews {
        val p = prefs(context)
        val fresh = p.getString("md_date", null) == today()
        return RemoteViews(context.packageName, R.layout.widget_mood).apply {
            setTextViewText(R.id.mood_title, p.text("md_title", "How was today?"))
            setTextViewText(R.id.mood_sub, if (fresh) p.text("md_sub") else p.text("md_new"))
            moodButtons.forEachIndexed { i, id ->
                setContentDescription(id, p.text("md${i + 1}", moodNames[i]))
                setOnClickPendingIntent(id, launch(context, ACTION_MOOD, "${i + 1}", 30 + i))
            }
            setOnClickPendingIntent(R.id.mood_root, launch(context, null, null, 0))
        }
    }

    private fun launch(context: Context, action: String?, target: String?, code: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = action ?: Intent.ACTION_MAIN
            if (target != null) putExtra(EXTRA_TARGET, target)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

/** Every widget redraws from what the app last sent (and checks the date again). */
abstract class CatalystWidgetBase : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, Widgets.views(context, javaClass))
    }
}

class CatalystWidget : CatalystWidgetBase()
class MonthWidget : CatalystWidgetBase()
class WalletsWidget : CatalystWidgetBase()
class BillsWidget : CatalystWidgetBase()
class MoodWidget : CatalystWidgetBase()
