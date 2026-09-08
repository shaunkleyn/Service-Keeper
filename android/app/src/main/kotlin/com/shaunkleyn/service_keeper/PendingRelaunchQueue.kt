package com.shaunkleyn.service_keeper

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Holds app-relaunch attempts that were deferred because the device wasn't
 * idle (per the current relaunch-idle mode) at detection time. Drained by
 * KeeperForegroundService's periodic poll once idle, or immediately on
 * ACTION_USER_PRESENT for the "locked" mode.
 */
object PendingRelaunchQueue {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val QUEUE_KEY = "flutter.pending_locked_relaunches"

    @Synchronized
    fun hasPending(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(QUEUE_KEY, null) ?: return false
        return try {
            JSONArray(raw).length() > 0
        } catch (_: Exception) {
            false
        }
    }

    data class Entry(
        val packageName: String,
        val serviceClass: String,
        val label: String,
        val notifEnabled: Boolean
    )

    @Synchronized
    fun enqueue(context: Context, entry: Entry) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val arr = try {
            JSONArray(prefs.getString(QUEUE_KEY, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        // Avoid piling up duplicate entries for the same service.
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            if (obj.optString("packageName") == entry.packageName &&
                obj.optString("serviceClass") == entry.serviceClass
            ) {
                return
            }
        }
        arr.put(JSONObject().apply {
            put("packageName", entry.packageName)
            put("serviceClass", entry.serviceClass)
            put("label", entry.label)
            put("notifEnabled", entry.notifEnabled)
        })
        prefs.edit().putString(QUEUE_KEY, arr.toString()).apply()
    }

    @Synchronized
    fun drainAll(context: Context): List<Entry> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(QUEUE_KEY, null) ?: return emptyList()
        prefs.edit().remove(QUEUE_KEY).apply()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val obj = arr.getJSONObject(i)
                Entry(
                    packageName = obj.getString("packageName"),
                    serviceClass = obj.getString("serviceClass"),
                    label = obj.optString("label", obj.getString("packageName")),
                    notifEnabled = obj.optBoolean("notifEnabled", true)
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
