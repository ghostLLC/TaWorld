package com.taworld.taworld

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val BACKGROUND_CHANNEL = "com.taworld.taworld/background_execution"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBackgroundReadiness" -> result.success(backgroundReadiness())
                "openNotificationSettings" -> result.success(
                    openSystemIntent(notificationSettingsIntent()),
                )
                "openExactAlarmSettings" -> result.success(
                    openSystemIntent(exactAlarmSettingsIntent()),
                )
                "openBatteryOptimizationSettings" -> result.success(
                    openSystemIntent(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)),
                )
                "openAutoStartSettings" -> result.success(
                    findAutoStartIntent()?.let(::openSystemIntent)
                        ?: openSystemIntent(applicationDetailsIntent()),
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun backgroundReadiness(): Map<String, Any> {
        val notificationManager = getSystemService(NotificationManager::class.java)
        val notificationGranted = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N ->
                notificationManager.areNotificationsEnabled()
            else -> true
        }

        val alarmManager = getSystemService(AlarmManager::class.java)
        val exactAlarmAllowed =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

        val powerManager = getSystemService(PowerManager::class.java)
        val batteryOptimizationIgnored =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                powerManager.isIgnoringBatteryOptimizations(packageName)

        return mapOf(
            "notificationGranted" to notificationGranted,
            "exactAlarmAllowed" to exactAlarmAllowed,
            "batteryOptimizationIgnored" to batteryOptimizationIgnored,
            "autoStartGuidanceAvailable" to (findAutoStartIntent() != null),
            // Android has no public API for reading OEM autostart grant state.
            "autoStartStatusKnown" to false,
            "manufacturer" to Build.MANUFACTURER,
            // WorkManager remains subject to Doze and OEM background limits.
            "bestEffort" to true,
        )
    }

    private fun notificationSettingsIntent(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            applicationDetailsIntent()
        }

    private fun exactAlarmSettingsIntent(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:$packageName"),
            )
        } else {
            applicationDetailsIntent()
        }

    private fun applicationDetailsIntent(): Intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:$packageName"),
    )

    private fun findAutoStartIntent(): Intent? {
        val candidates = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            ),
            ComponentName(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            ),
            ComponentName(
                "com.meizu.safe",
                "com.meizu.safe.security.SHOW_APPSEC",
            ),
        )
        return candidates
            .asSequence()
            .map { component -> Intent().setComponent(component) }
            .firstOrNull { intent ->
                intent.resolveActivity(packageManager) != null
            }
    }

    private fun openSystemIntent(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }
}
