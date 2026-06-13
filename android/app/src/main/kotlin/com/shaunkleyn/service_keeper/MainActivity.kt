package com.shaunkleyn.service_keeper

import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku

class MainActivity : FlutterActivity() {
    private val channel = "com.shaunkleyn.service_keeper/shizuku"
    private val shizukuPermCode = 1001

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
                        val serviceList = mutableListOf<Map<String, String?>>()
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
                                serviceList.add(mapOf("p" to pkg.packageName, "c" to svc.name, "n" to appName))
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
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Shizuku.removeRequestPermissionResultListener(shizukuPermListener)
    }
}
