package com.havic47.catalyst

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Two small channels for the Flutter side:
// - catalyst/sms: a bKash / Nagad message the user shared to the app (Messages →
//   press and hold → Share → Catalyst). Only that text arrives — the app has no
//   SMS permission and reads nothing else; it's parsed on the phone.
// - catalyst/widget: the home-screen widgets' figures (Widgets.kt), and a widget
//   tap handed to the app: "add", "open:<section>" or "mood:<1-5>". Also the
//   phone's timezone ("Asia/Dhaka"), which recurring entries keep their time in.
class MainActivity : FlutterActivity() {
    private var smsChannel: MethodChannel? = null
    private var widgetChannel: MethodChannel? = null
    private var launchAction: String? = null
    private var sharedText: String? = null
    private var restored = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Brought back after Android closed it: the share or widget tap it was opened
        // with is old news.
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchAction = if (restored) null else actionOf(intent)
        sharedText = if (restored) null else textOf(intent)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        smsChannel = MethodChannel(messenger, "catalyst/sms").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "sharedText" -> {
                        result.success(sharedText)
                        sharedText = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        widgetChannel = MethodChannel(messenger, "catalyst/widget").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        Widgets.save(this@MainActivity, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        result.success(null)
                    }
                    "launchAction" -> {
                        result.success(launchAction)
                        launchAction = null
                    }
                    "timezone" -> result.success(java.util.TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        actionOf(intent)?.let { widgetChannel?.invokeMethod("action", it) }
        textOf(intent)?.let { smsChannel?.invokeMethod("shared", it) }
    }

    private fun actionOf(intent: Intent?): String? {
        val target = intent?.getStringExtra(Widgets.EXTRA_TARGET)
        return when (intent?.action) {
            Widgets.ACTION_ADD -> "add"
            Widgets.ACTION_OPEN -> target?.let { "open:$it" }
            Widgets.ACTION_MOOD -> target?.let { "mood:$it" }
            else -> null
        }
    }

    /** The text shared to the app (Share → Catalyst), when this intent carries some. */
    private fun textOf(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }?.take(MAX_TEXT)
        } else {
            null
        }

    companion object {
        private const val MAX_TEXT = 5000
    }
}
