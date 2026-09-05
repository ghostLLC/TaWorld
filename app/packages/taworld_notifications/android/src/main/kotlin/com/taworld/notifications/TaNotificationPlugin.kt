package com.taworld.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Alarm publication and actions never depend on a live Flutter engine. */
class TaNotificationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.NewIntentListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var activity: ActivityPluginBinding? = null
    private var launchPayload: String? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.taworld.taworld/notification_ledger")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null) }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
        onNewIntent(binding.activity.intent)
    }
    override fun onDetachedFromActivity() { activity?.removeOnNewIntentListener(this); activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onNewIntent(intent: Intent): Boolean {
        val payload = intent.getStringExtra("taworld_notification_payload") ?: return false
        launchPayload = payload
        intent.removeExtra("taworld_notification_payload")
        channel.invokeMethod("notificationOpened", payload)
        return true
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val store = TaNotificationStore(context)
            when (call.method) {
                "schedule" -> { store.schedule(JSONObject(call.arguments as Map<*, *>)); result.success(true) }
                "show" -> result.success(store.publish(JSONObject(call.arguments as Map<*, *>)))
                "pending" -> result.success(store.pending().map(::jsonMap))
                "events" -> result.success(store.events().map(::jsonMap))
                "ackEvents" -> { store.ackEvents((call.arguments as List<*>).filterIsInstance<String>().toSet()); result.success(true) }
                "cancel" -> { store.cancel((call.arguments as Number).toInt()); result.success(true) }
                "cancelAll" -> { store.cancelAll(); result.success(true) }
                "restore" -> { store.restore(); result.success(true) }
                "clearEvidence" -> { store.clear(); result.success(true) }
                "active" -> result.success(store.active())
                "channelAllowed" -> result.success(store.channelAllowed(call.arguments as? String ?: TaNotificationStore.CHANNEL))
                "launchPayload" -> { result.success(launchPayload); launchPayload = null }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("NOTIFICATION_OPERATION_FAILED", error.javaClass.simpleName, null)
        }
    }
}

private fun jsonMap(data: JSONObject): Map<String, Any?> = data.keys().asSequence().associateWith {
    val value = data.opt(it)
    if (value == JSONObject.NULL) null else value
}

internal class TaNotificationStore(private val context: Context) {
    companion object { const val CHANNEL = "taworld_reminders" }
    private val prefs = context.getSharedPreferences("TaWorldNotificationLedger", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private fun pushEnabled(): Boolean = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getBoolean("flutter.push_enabled", true)
    fun allowed(channel: String = CHANNEL): Boolean = pushEnabled() && channelAllowed(channel)
    fun channelAllowed(channel: String = CHANNEL): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(channel)?.importance != NotificationManager.IMPORTANCE_NONE
    }
    private fun alarmIntent(id: Int): PendingIntent = PendingIntent.getBroadcast(context, id,
        Intent(context, TaReminderReceiver::class.java).putExtra("notification_id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun schedule(data: JSONObject) {
        val id = data.getInt("id")
        val at = data.getLong("at")
        if (at <= System.currentTimeMillis()) throw IllegalArgumentException("Past reminder")
        if (!pushEnabled()) throw IllegalStateException("Notifications disabled")
        val pending = alarmIntent(id)
        val exact = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()
        val previous = prefs.getString("pending:$id", null)
        check(prefs.edit().putString("pending:$id", data.toString()).commit())
        try {
            if (exact) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            event(data, "scheduled", if (exact) "exact" else "inexact")
        } catch (error: Exception) {
            prefs.edit().apply { if (previous == null) remove("pending:$id") else putString("pending:$id", previous) }.commit()
            event(data, "schedule_failed", error.javaClass.simpleName)
            throw error
        }
    }
    fun pending(): List<JSONObject> = prefs.all.filterKeys { it.startsWith("pending:") }.values.mapNotNull {
        try { JSONObject(it as String) } catch (_: Exception) { null }
    }
    fun publish(data: JSONObject): Boolean {
        val id = data.getInt("id")
        val channelId = data.optString("channel", CHANNEL)
        prefs.edit().remove("pending:$id").commit()
        if (!allowed(channelId)) { event(data, "blocked_permission"); return false }
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(channelId, if (channelId == CHANNEL) "Ta的提醒" else "主动关心", NotificationManager.IMPORTANCE_HIGH))
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!.apply {
            putExtra("taworld_notification_payload", data.optString("payload"))
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val open = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val smallIcon = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
            .takeIf { it != 0 } ?: context.applicationInfo.icon
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(smallIcon).setContentTitle(data.getString("title"))
            .setContentText(data.getString("body")).setStyle(NotificationCompat.BigTextStyle().bigText(data.getString("body")))
            .setPriority(NotificationCompat.PRIORITY_HIGH).setAutoCancel(true).setContentIntent(open)
        if (data.optString("payload").startsWith("occurrenceId:")) {
            for ((action, label) in listOf("done" to "关心过了", "snooze" to "5分钟后", "outdated" to "过时了")) {
                val actionIntent = Intent(context, TaReminderActionReceiver::class.java)
                    .setAction("${context.packageName}.reminder.$action")
                    .putExtra("notification_id", id).putExtra("generation", data.optLong("at"))
                val button = PendingIntent.getBroadcast(context, id, actionIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                builder.addAction(0, label, button)
            }
        }
        try {
            check(prefs.edit().putString("displayed:$id", data.toString()).commit())
            manager.notify(id, builder.build())
            event(data, "posted_to_system")
            if (manager.activeNotifications.any { it.id == id }) event(data, "observed_in_tray")
            return true
        } catch (error: Exception) { event(data, "publish_failed", error.javaClass.simpleName); return false }
    }
    fun fire(id: Int) {
        val raw = prefs.getString("pending:$id", null) ?: return
        publish(JSONObject(raw))
    }
    fun respond(id: Int, generation: Long, action: String) {
        val raw = prefs.getString("displayed:$id", null) ?: return
        val data = JSONObject(raw)
        if (data.optLong("at") != generation) return
        // Clearing this generation before processing deduplicates button replays.
        check(prefs.edit().remove("displayed:$id").commit())
        manager.cancel(id)
        if (action == "snooze") {
            data.put("at", System.currentTimeMillis() + 5 * 60 * 1000).put("kind", "snooze")
            try { schedule(data); event(data, "action_snooze", data.getLong("at").toString()) }
            catch (_: Exception) { event(data, "snooze_failed") }
        } else if (action == "done" || action == "outdated") { event(data, "action_$action") }
    }
    fun restore() {
        for (data in pending()) {
            if (data.getLong("at") <= System.currentTimeMillis()) {
                prefs.edit().remove("pending:${data.getInt("id")}").commit()
                event(data, "historical_unknown", "expired_before_restore")
            } else try { schedule(data) } catch (_: Exception) { /* retained for repair */ }
        }
    }
    fun cancel(id: Int) {
        val raw = prefs.getString("pending:$id", null)
        alarms.cancel(alarmIntent(id)); manager.cancel(id)
        prefs.edit().remove("pending:$id").remove("displayed:$id").commit()
        if (raw != null) event(JSONObject(raw), "cancelled")
    }
    fun cancelAll() {
        pending().forEach { cancel(it.getInt("id")) }
        prefs.all.keys.filter { it.startsWith("displayed:") }.forEach { cancel(it.substringAfter(':').toInt()) }
    }
    fun clear() { cancelAll(); prefs.edit().clear().commit() }
    fun active(): List<Map<String, Any?>> = manager.activeNotifications.map { mapOf("id" to it.id, "postedAt" to it.postTime) }
    private fun event(data: JSONObject, kind: String, detail: String? = null) {
        val all = JSONArray(prefs.getString("events", "[]")); val retained = JSONArray()
        for (i in maxOf(0, all.length() - 1999) until all.length()) retained.put(all.getJSONObject(i))
        retained.put(JSONObject().put("id", UUID.randomUUID().toString())
            .put("notificationId", data.optInt("id")).put("payload", data.optString("payload"))
            .put("kind", kind).put("at", System.currentTimeMillis()).put("detail", detail ?: JSONObject.NULL))
        check(prefs.edit().putString("events", retained.toString()).commit())
    }
    fun events(): List<JSONObject> {
        val data = JSONArray(prefs.getString("events", "[]"))
        return (0 until data.length()).map { data.getJSONObject(it) }
    }
    fun ackEvents(ids: Set<String>) {
        val retained = JSONArray(); events().filter { it.getString("id") !in ids }.forEach { retained.put(it) }
        check(prefs.edit().putString("events", retained.toString()).commit())
    }
}
class TaReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { TaNotificationStore(context).fire(intent.getIntExtra("notification_id", -1)) }
}
class TaReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TaNotificationStore(context).respond(intent.getIntExtra("notification_id", -1),
            intent.getLongExtra("generation", -1), intent.action?.substringAfterLast('.') ?: "")
    }
}
class TaReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { TaNotificationStore(context).restore() }
}
