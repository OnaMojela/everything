package com.everything.everything

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures notifications that look like they mention money and queues them for
 * the Flutter side to parse.
 *
 * Deliberately conservative: anything without a currency amount is dropped
 * immediately and never stored, and the user can mute individual apps. The
 * queue lives in app-private storage and never leaves the device.
 */
class TransactionNotificationListener : NotificationListenerService() {

    companion object {
        const val PREFS = "notification_capture"
        const val KEY_QUEUE = "queue"
        const val KEY_ENABLED = "capture_enabled"
        const val KEY_MUTED = "muted_packages"
        private const val MAX_QUEUE = 200

        /** Cheap pre-filter: does this text mention an amount of money? */
        private val MONEY = Regex(
            """(?<![A-Za-z0-9])(ZAR|USD|EUR|GBP|R|\$|£|€)\s?\d""",
            RegexOption.IGNORE_CASE,
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return // never capture our own notifications

        val muted = prefs.getString(KEY_MUTED, "") ?: ""
        if (muted.split(",").any { it.isNotBlank() && it == pkg }) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString().orEmpty()
        val text = extras.getCharSequence("android.text")?.toString().orEmpty()
        val bigText = extras.getCharSequence("android.bigText")?.toString().orEmpty()
        val body = if (bigText.length > text.length) bigText else text

        // Drop anything that doesn't mention money before it is ever stored.
        if (!MONEY.containsMatchIn("$title $body")) return

        val item = JSONObject().apply {
            put("package", pkg)
            put("appLabel", appLabel(pkg))
            put("title", title)
            put("body", body)
            put("postedAt", sbn.postTime)
            put("key", "$pkg|${sbn.postTime}|${body.hashCode()}")
        }

        synchronized(this) {
            val queue = try {
                JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            } catch (e: Exception) {
                JSONArray()
            }
            // Skip duplicates (updates to the same notification re-post it).
            val key = item.getString("key")
            for (i in 0 until queue.length()) {
                if (queue.optJSONObject(i)?.optString("key") == key) return
            }
            queue.put(item)
            // Keep the queue bounded — drop the oldest entries.
            val trimmed = if (queue.length() > MAX_QUEUE) {
                JSONArray().also { out ->
                    for (i in queue.length() - MAX_QUEUE until queue.length()) {
                        out.put(queue.get(i))
                    }
                }
            } else {
                queue
            }
            prefs.edit().putString(KEY_QUEUE, trimmed.toString()).apply()
        }
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }
}
