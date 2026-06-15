package com.shaunkleyn.service_keeper

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku

class MainActivity : FlutterActivity() {
    private val channel = "com.shaunkleyn.service_keeper/shizuku"
    private val shizukuPermCode = 1001
    private val notifPermCode = 1002
    private var pendingNotifResult: MethodChannel.Result? = null

    private val shizukuPermListener = Shizuku.OnRequestPermissionResultListener { _, result ->
        // Permission result handled; Flutter side will re-check via checkPermission
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Shizuku.addRequestPermissionResultListener(shizukuPermListener)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "execCommand" -> {
                    val command = call.argument<String>("command")
                    if (command == null) {
                        result.error("INVALID_ARGS", "command required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        val output = ShizukuExecutor.exec(command)
                        runOnUiThread {
                            if (output != null) result.success(output)
                            else result.error("EXEC_FAILED", "Shizuku exec returned null", null)
                        }
                    }.start()
                }
                "getInstalledServices" -> {
                    val includeSystem = call.argument<Boolean>("includeSystem") ?: false
                    Thread {
                        val pm = packageManager
                        val packages = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                            pm.getInstalledPackages(android.content.pm.PackageManager.PackageInfoFlags.of(android.content.pm.PackageManager.GET_SERVICES.toLong()))
                        } else {
                            @Suppress("DEPRECATION")
                            pm.getInstalledPackages(android.content.pm.PackageManager.GET_SERVICES)
                        }
                        val serviceList = mutableListOf<Map<String, Any?>>()
                        for (pkg in packages) {
                            val services = pkg.services
                            if (services.isNullOrEmpty()) continue
                            val appInfo = pkg.applicationInfo ?: continue
                            val isSystem = appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM != 0
                            if (!includeSystem && isSystem) continue
                            val appName = try {
                                pm.getApplicationLabel(appInfo).toString()
                            } catch (e: Exception) { pkg.packageName }
                            for (svc in services) {
                                serviceList.add(mapOf(
                                    "p" to pkg.packageName,
                                    "c" to svc.name,
                                    "n" to appName,
                                    "e" to svc.exported,
                                    "pm" to (svc.permission ?: ""),
                                ))
                            }
                        }
                        runOnUiThread { result.success(serviceList) }
                    }.start()
                }
                "getAppName" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName == null) { result.error("INVALID_ARGS", "packageName required", null); return@setMethodCallHandler }
                    try {
                        val info = packageManager.getApplicationInfo(pkgName, 0)
                        result.success(packageManager.getApplicationLabel(info).toString())
                    } catch (e: Exception) { result.success(null) }
                }
                "getAppIcon" -> {
                    val pkgName = call.argument<String>("packageName")
                    if (pkgName == null) {
                        result.error("INVALID_ARGS", "packageName required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val drawable = packageManager.getApplicationIcon(pkgName)
                        val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 48
                        val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 48
                        val bmp = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
                        val canvas = android.graphics.Canvas(bmp)
                        drawable.setBounds(0, 0, w, h)
                        drawable.draw(canvas)
                        val stream = java.io.ByteArrayOutputStream()
                        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(stream.toByteArray())
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "isBatteryOptimizationExempt" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryOptimizationExemption" -> {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "startKeeperService" -> {
                    val count = call.argument<Int>("count") ?: 0
                    KeeperForegroundService.start(applicationContext, count)
                    result.success(null)
                }
                "stopKeeperService" -> {
                    KeeperForegroundService.stop(applicationContext)
                    result.success(null)
                }
                "scheduleMonitorWork" -> {
                    val pkg = call.argument<String>("packageName")
                    val cls = call.argument<String>("serviceClass")
                    val label = call.argument<String>("displayLabel")
                    val interval = call.argument<Int>("intervalMinutes") ?: 15
                    if (pkg == null || cls == null || label == null) {
                        result.error("INVALID_ARGS", "packageName/serviceClass/displayLabel required", null)
                        return@setMethodCallHandler
                    }

                    val tag = "${pkg}_${cls.replace('.', '_')}"
                    val data = androidx.work.Data.Builder()
                        .putString("packageName", pkg)
                        .putString("serviceClass", cls)
                        .putString("displayLabel", label)
                        .putLong("intervalMinutes", interval.toLong())
                        .putBoolean("selfChain", interval < 15)
                        .build()

                    if (interval >= 15) {
                        MonitorWorker.schedule(applicationContext, tag, interval.toLong(), data)
                    } else {
                        MonitorWorker.scheduleOnce(applicationContext, tag, interval.toLong(), data)
                    }
                    result.success(null)
                }
                "cancelMonitorWork" -> {
                    val workTag = call.argument<String>("workTag")
                    if (workTag == null) {
                        result.error("INVALID_ARGS", "workTag required", null)
                        return@setMethodCallHandler
                    }
                    MonitorWorker.cancel(applicationContext, workTag)
                    result.success(null)
                }
                "rescheduleAllMonitorWork" -> {
                    MonitorWorker.scheduleAllFromPrefs(applicationContext)
                    result.success(null)
                }
                "runMonitorNowForAll" -> {
                    val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val raw = prefs.getString("flutter.monitored_services", null)
                    if (raw == null) {
                        result.success(0)
                        return@setMethodCallHandler
                    }

                    var count = 0
                    try {
                        val arr = org.json.JSONArray(raw)
                        for (i in 0 until arr.length()) {
                            val obj = arr.getJSONObject(i)
                            if (!obj.optBoolean("enabled", true)) continue
                            val pkg = obj.getString("packageName")
                            val cls = obj.getString("serviceClass")
                            val label = obj.getString("displayLabel")
                            val tag = "${pkg}_${cls.replace('.', '_')}"

                            val data = androidx.work.Data.Builder()
                                .putString("packageName", pkg)
                                .putString("serviceClass", cls)
                                .putString("displayLabel", label)
                                .putLong("intervalMinutes", obj.optInt("intervalMinutes", 15).toLong())
                                .putBoolean("selfChain", false)
                                .build()

                            MonitorWorker.runNow(applicationContext, tag, data)
                            count++
                        }
                    } catch (_: Exception) {
                        // Return how many jobs were enqueued before failure.
                    }
                    result.success(count)
                }
                "checkNotificationPermission" -> {
                    result.success(
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU)
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                        else true
                    )
                }
                "requestNotificationPermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        pendingNotifResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                            notifPermCode
                        )
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notifPermCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotifResult?.success(granted)
            pendingNotifResult = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Shizuku.removeRequestPermissionResultListener(shizukuPermListener)
    }
}
