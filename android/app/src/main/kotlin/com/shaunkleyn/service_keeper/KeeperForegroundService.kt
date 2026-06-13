package com.shaunkleyn.service_keeper

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class KeeperForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "keeper_persistent"
        private const val NOTIF_ID = 1
        private const val EXTRA_COUNT = "serviceCount"

        fun start(context: Context, serviceCount: Int? = null) {
            val count = serviceCount ?: readCountFromPrefs(context)
            val intent = Intent(context, KeeperForegroundService::class.java)
                .putExtra(EXTRA_COUNT, count)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KeeperForegroundService::class.java))
        }

        private fun readCountFromPrefs(context: Context): Int {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val raw = prefs.getString("flutter.monitored_services", null) ?: return 0
            return try { org.json.JSONArray(raw).length() } catch (_: Exception) { 0 }
        }
    }

    private var currentCount = 0

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentCount = intent?.getIntExtra(EXTRA_COUNT, currentCount) ?: currentCount
        ensureChannel()
        startForeground(NOTIF_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID, "Service Keeper", NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Service Keeper is actively monitoring background services" }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification() = run {
        val tapIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val text = if (currentCount == 0) "No services configured"
                   else "Monitoring $currentCount service${if (currentCount == 1) "" else "s"}"
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle("Service Keeper")
            .setContentText(text)
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
