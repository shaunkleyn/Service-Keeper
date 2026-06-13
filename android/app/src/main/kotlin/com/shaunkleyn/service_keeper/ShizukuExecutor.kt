package com.shaunkleyn.service_keeper

import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

object ShizukuExecutor {

    fun isReady(): Boolean = try {
        Shizuku.pingBinder() && Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED
    } catch (e: Exception) {
        false
    }

    fun exec(command: String): String? {
        if (!isReady()) return null
        return try {
            val process = ShizukuHelper.newProcess(
                arrayOf("sh", "-c", command),
                null,
                "/"
            )
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                output.appendLine(line)
            }
            process.waitFor()
            output.toString()
        } catch (e: Exception) {
            null
        }
    }

    fun isServiceRunning(packageName: String, serviceClass: String): Boolean {
        val output = exec("dumpsys activity services $packageName") ?: return false
        return output.contains(serviceClass)
    }

    fun startService(packageName: String, serviceClass: String): Boolean {
        val component = "$packageName/$serviceClass"
        val result = exec("am start-foreground-service -n $component")
        if (result == null || result.contains("Error", ignoreCase = true)) {
            // Fallback for older APIs or non-foreground services
            val fallback = exec("am startservice -n $component")
            return fallback != null && !fallback.contains("Error", ignoreCase = true)
        }
        return true
    }
}
