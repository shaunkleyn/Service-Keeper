package com.shaunkleyn.service_keeper

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/**
 * Decides whether the device is "idle" enough to relaunch an app without
 * interrupting the user, per the user-selected relaunch-idle mode.
 *
 * Modes (mirrors the Dart-side `relaunch_idle_mode` setting):
 * - "always": never gate, relaunch immediately.
 * - "no_foreground_app": idle only when the launcher/home screen is in front.
 * - "inactivity": idle only after N seconds with no touch/key input anywhere
 *   on the device (uses PowerManagerService's own activity timer via dumpsys,
 *   since that's what taps/scrolls/key presses actually reset - unlike
 *   UsageEvents.USER_INTERACTION, which does not fire reliably for ongoing
 *   in-app scrolling and was found to misreport "idle" during active use).
 * - "locked": idle only while the keyguard is showing. The caller is expected
 *   to defer to PendingRelaunchQueue when this reports not-idle, so the
 *   relaunch happens right on the next unlock instead of being silently lost.
 */
object DeviceIdleChecker {

    private const val PREFS_NAME = "FlutterSharedPreferences"

    fun getConfiguredMode(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString("flutter.relaunch_idle_mode", "inactivity") ?: "inactivity"
    }

    /** Reads the user's configured mode/threshold from prefs and evaluates isIdle() with them. */
    fun isIdleFromPrefs(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val inactivitySeconds = prefs.getLong("flutter.relaunch_inactivity_seconds", 60L).toInt()
        return isIdle(context, getConfiguredMode(context), inactivitySeconds)
    }

    fun isIdle(context: Context, mode: String, inactivitySeconds: Int): Boolean {
        return when (mode) {
            "always" -> true
            "no_foreground_app" -> isForegroundAppLauncher(context)
            "inactivity" -> {
                val ms = msSinceLastUserActivity() ?: return false // unknown -> assume active
                ms >= inactivitySeconds * 1000L
            }
            "locked" -> isKeyguardLocked(context)
            else -> false
        }
    }

    private fun isForegroundAppLauncher(context: Context): Boolean {
        val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
        val homePkg = resolved?.activityInfo?.packageName ?: return false
        val foreground = ShizukuExecutor.getForegroundApp() ?: return false
        return foreground.first == homePkg
    }

    /** Milliseconds since the last touch/key input anywhere on the device, or null if unknown. */
    private fun msSinceLastUserActivity(): Long? {
        val output = ShizukuExecutor.exec("dumpsys power") ?: return null
        val re = Regex("""lastUserActivityTime=\d+ \((\d+) ms ago\)""")
        val match = re.find(output) ?: return null
        return match.groupValues[1].toLongOrNull()
    }

    fun isKeyguardLocked(context: Context): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return km.isKeyguardLocked
    }
}
