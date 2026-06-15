package com.shaunkleyn.service_keeper

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import androidx.core.app.NotificationCompat
import androidx.work.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class MonitorWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val SERVICES_KEY = "flutter.monitored_services"
        private const val AUDIT_KEY = "flutter.pending_audit_events"
        private const val CHANNEL_ID = "service_keeper_channel"
        private const val CHANNEL_NAME = "Service Keeper"
        private var notifId = 1000

        fun schedule(context: Context, workTag: String, intervalMinutes: Long, inputData: Data) {
            val request = PeriodicWorkRequestBuilder<MonitorWorker>(
                intervalMinutes, TimeUnit.MINUTES
            )
                .addTag(workTag)
                .setInputData(inputData)
                .setConstraints(Constraints.NONE)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                workTag,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }

        fun scheduleOnce(context: Context, workTag: String, delayMinutes: Long, inputData: Data) {
            val request = OneTimeWorkRequestBuilder<MonitorWorker>()
                .addTag(workTag)
                .setInputData(inputData)
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "${workTag}_once",
                ExistingWorkPolicy.REPLACE,
                request
            )
        }

        fun cancel(context: Context, workTag: String) {
            WorkManager.getInstance(context).cancelAllWorkByTag(workTag)
        }

        fun runNow(context: Context, workTag: String, inputData: Data) {
            val request = OneTimeWorkRequestBuilder<MonitorWorker>()
                .addTag(workTag)
                .setInputData(inputData)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                "${workTag}_now",
                ExistingWorkPolicy.REPLACE,
                request
            )
        }

        fun scheduleAllFromPrefs(context: Context) {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString(SERVICES_KEY, null) ?: return
            try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    if (!obj.optBoolean("enabled", true)) continue
                    val pkg = obj.getString("packageName")
                    val cls = obj.getString("serviceClass")
                    val label = obj.getString("displayLabel")
                    val interval = obj.optInt("intervalMinutes", 15).toLong()
                    val tag = "${pkg}_${cls.replace('.', '_')}"
                    val data = Data.Builder()
                        .putString("packageName", pkg)
                        .putString("serviceClass", cls)
                        .putString("displayLabel", label)
                        .putLong("intervalMinutes", interval)
                        .putBoolean("selfChain", interval < 15)
                        .build()

                    if (interval >= 15) {
                        schedule(context, tag, interval, data)
                    } else {
                        scheduleOnce(context, tag, interval, data)
                    }
                }
            } catch (_: Exception) { }
        }
    }

    override fun doWork(): Result {
        val pkg = inputData.getString("packageName") ?: return Result.failure()
        val cls = inputData.getString("serviceClass") ?: return Result.failure()
        val label = inputData.getString("displayLabel") ?: pkg
        val selfChain = inputData.getBoolean("selfChain", false)
        val intervalMinutes = inputData.getLong("intervalMinutes", 15L)

        if (!ShizukuExecutor.isReady()) return Result.retry()

        val running = ShizukuExecutor.isServiceRunning(pkg, cls)
        if (!running) {
            appendAuditEvent(pkg, cls, label, "DETECTED_STOPPED", "AUTOMATIC", null)
            appendAuditEvent(pkg, cls, label, "RESTART_ATTEMPTED", "AUTOMATIC", null)
            val start = ShizukuExecutor.startServiceDetailed(pkg, cls)
            if (start.ok) {
                appendAuditEvent(pkg, cls, label, "RESTART_SUCCESS", "AUTOMATIC", start.detail)
                sendNotification(label, "Restarted $label — service was not running.")
            } else {
                appendAuditEvent(pkg, cls, label, "RESTART_FAILED", "AUTOMATIC", start.detail)
            }
        }

        // Self-chain for sub-15-min intervals
        if (selfChain) {
            val tag = "${pkg}_${cls.replace('.', '_')}"
            scheduleOnce(applicationContext, tag, intervalMinutes, inputData)
        }

        return Result.success()
    }

    private fun appendAuditEvent(
        pkg: String, cls: String, lbl: String,
        evt: String, trg: String, notes: String?
    ) {
        try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existing = prefs.getString(AUDIT_KEY, "[]")
            val arr = JSONArray(existing)
            val obj = JSONObject().apply {
                put("ts", java.time.Instant.now().toString())
                put("pkg", pkg)
                put("cls", cls)
                put("lbl", lbl)
                put("evt", evt)
                put("trg", trg)
                if (notes != null) put("notes", notes)
            }
            arr.put(obj)
            prefs.edit().putString(AUDIT_KEY, arr.toString()).apply()
        } catch (_: Exception) {}
    }

    private fun sendNotification(title: String, text: String) {
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager

        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Service restart notifications" }
        nm.createNotificationChannel(channel)

        val notif = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()

        nm.notify(notifId++, notif)
    }
}
