package com.everything.everything

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

/** FlutterFragmentActivity is required by local_auth for the biometric prompt. */
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "everything/notification_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences(
                    TransactionNotificationListener.PREFS, Context.MODE_PRIVATE
                )
                when (call.method) {
                    "hasPermission" -> result.success(hasNotificationAccess())

                    "openSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }

                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        prefs.edit()
                            .putBoolean(TransactionNotificationListener.KEY_ENABLED, enabled)
                            .apply()
                        result.success(null)
                    }

                    "setMutedPackages" -> {
                        val list = call.argument<List<String>>("packages").orEmpty()
                        prefs.edit()
                            .putString(
                                TransactionNotificationListener.KEY_MUTED,
                                list.joinToString(",")
                            )
                            .apply()
                        result.success(null)
                    }

                    // Returns everything captured since the last drain, then clears it.
                    "drain" -> {
                        val raw = prefs.getString(
                            TransactionNotificationListener.KEY_QUEUE, "[]"
                        ) ?: "[]"
                        prefs.edit()
                            .putString(TransactionNotificationListener.KEY_QUEUE, "[]")
                            .apply()
                        result.success(itemsFrom(raw))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun itemsFrom(raw: String): List<Map<String, Any?>> = try {
        val array = JSONArray(raw)
        (0 until array.length()).mapNotNull { i ->
            array.optJSONObject(i)?.let { o ->
                mapOf(
                    "package" to o.optString("package"),
                    "appLabel" to o.optString("appLabel"),
                    "title" to o.optString("title"),
                    "body" to o.optString("body"),
                    "postedAt" to o.optLong("postedAt"),
                    "key" to o.optString("key"),
                )
            }
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return enabled.split(":").any { it.contains(packageName) }
    }
}
