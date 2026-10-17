package com.havic47.catalyst

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Two small channels for the Flutter side:
// - catalyst/sms: opt-in reading of bKash / Nagad messages. Only messages from
//   those senders are read, only after the user turns it on and grants READ_SMS,
//   and they're parsed on the phone — nothing here sends them anywhere.
// - catalyst/widget: the home-screen widget's figures, and the widget's
//   "quick add" tap handed to the app.
class MainActivity : FlutterActivity() {
    private var smsPermissionResult: MethodChannel.Result? = null
    private var widgetChannel: MethodChannel? = null
    private var launchAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchAction = actionOf(intent)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "catalyst/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else {
                        smsPermissionResult?.success(false)
                        smsPermissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.READ_SMS), SMS_REQUEST)
                    }
                }
                "read" -> {
                    if (!hasSmsPermission()) {
                        result.error("permission", "READ_SMS not granted", null)
                    } else {
                        val since = (call.argument<Number>("since"))?.toLong() ?: 0L
                        try {
                            result.success(readWalletMessages(since))
                        } catch (e: Exception) {
                            result.error("read", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        widgetChannel = MethodChannel(messenger, "catalyst/widget").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        CatalystWidget.save(this@MainActivity, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        result.success(null)
                    }
                    "launchAction" -> {
                        result.success(launchAction)
                        launchAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        actionOf(intent)?.let { widgetChannel?.invokeMethod("action", it) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_REQUEST) {
            smsPermissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            smsPermissionResult = null
        }
    }

    private fun actionOf(intent: Intent?): String? =
        if (intent?.action == CatalystWidget.ACTION_ADD) "add" else null

    private fun hasSmsPermission() = checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    /** Inbox messages from bKash / Nagad newer than [since] (ms), newest first. */
    private fun readWalletMessages(since: Long): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addressCol = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyCol = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateCol = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            var scanned = 0
            while (c.moveToNext() && scanned < MAX_SCAN && out.size < MAX_MESSAGES) {
                scanned++
                val address = c.getString(addressCol) ?: continue
                val sender = address.lowercase().replace(Regex("[^a-z0-9]"), "")
                if (SENDERS.none { sender.contains(it) }) continue
                out.add(
                    mapOf(
                        "id" to c.getLong(idCol).toString(),
                        "address" to address,
                        "body" to (c.getString(bodyCol) ?: ""),
                        "date" to c.getLong(dateCol),
                    ),
                )
            }
        }
        return out
    }

    companion object {
        private const val SMS_REQUEST = 4701
        private const val MAX_SCAN = 3000
        private const val MAX_MESSAGES = 300
        private val SENDERS = listOf("bkash", "nagad", "16247", "16167")
    }
}
