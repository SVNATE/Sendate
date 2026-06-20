package com.svnate.sendate

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * NotificationListenerService that captures notifications from all apps
 * and forwards them to connected devices via the background Dart engine.
 *
 * Mirrors phone notifications to the connected desktop/laptop.
 */
class SendateNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "SendateNotifListener"
        const val CHANNEL_NAME = "com.svnate.sendate/notification_listener"

        private var instance: SendateNotificationListener? = null
        private var methodChannel: MethodChannel? = null

        fun isRunning(): Boolean = instance != null

        /**
         * Set the MethodChannel from the background FlutterEngine.
         * Called by SendateForegroundService when it starts the background engine.
         */
        fun setMethodChannel(channel: MethodChannel) {
            methodChannel = channel
            Log.d(TAG, "MethodChannel set from background engine")
        }

        /**
         * Check if notification listener permission is granted.
         */
        fun isPermissionGranted(context: Context): Boolean {
            val cn = ComponentName(context, SendateNotificationListener::class.java)
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            return flat != null && flat.contains(cn.flattenToString())
        }

        /**
         * Open the notification listener settings page.
         */
        fun openPermissionSettings(context: Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        }

        /**
         * Execute a notification action (reply, dismiss, custom action) by index.
         * Called when a remote device forwards an action back to us.
         */
        fun performNotificationAction(notificationKey: String, actionIndex: Int) {
            val listener = instance ?: return
            try {
                val activeNotif = listener.activeNotifications?.find { it.key == notificationKey }
                    ?: return
                val action = activeNotif.notification.actions?.getOrNull(actionIndex) ?: return
                action.actionIntent?.send()
                Log.d(TAG, "Performed action[$actionIndex] on $notificationKey")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to perform action: ${e.message}")
            }
        }
    }

    // Packages to ignore (system notifications that shouldn't be synced)
    private val ignoredPackages = setOf(
        "com.svnate.sendate", // Don't sync our own notifications
        "android",
        "com.android.systemui",
        "com.android.providers.downloads",
    )

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "NotificationListener created")
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "NotificationListener destroyed")
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Notification listener connected")
        // Send currently active notifications
        try {
            val activeNotifications = activeNotifications
            Log.d(TAG, "Active notifications count: ${activeNotifications?.size ?: 0}")
        } catch (e: Exception) {
            Log.e(TAG, "Error getting active notifications: ${e.message}")
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return

        // Skip ignored packages
        if (sbn.packageName in ignoredPackages) return

        // Skip ongoing/persistent notifications (like music players, foreground services)
        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        // Skip group summary notifications
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        try {
            val data = extractNotificationData(sbn)
            Log.d(TAG, "Notification posted: ${data["appName"]} - ${data["title"]}")

            // Forward to Dart via MethodChannel
            methodChannel?.invokeMethod("onNotificationPosted", data)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification: ${e.message}", e)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName in ignoredPackages) return

        try {
            val data = mapOf(
                "id" to sbn.key,
                "packageName" to sbn.packageName,
            )
            methodChannel?.invokeMethod("onNotificationRemoved", data)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing notification removal: ${e.message}", e)
        }
    }

    private fun extractNotificationData(sbn: StatusBarNotification): Map<String, Any?> {
        val notification = sbn.notification
        val extras = notification.extras

        // Extract title and text
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()

        // Get app name
        val appName = try {
            val pm = applicationContext.packageManager
            val appInfo = pm.getApplicationInfo(sbn.packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
            sbn.packageName
        }

        // Extract small icon as base64 (optional, keep small)
        val iconBase64 = try {
            extractIconBase64(sbn)
        } catch (_: Exception) {
            null
        }

        // Extract actions
        val actions = notification.actions?.map { action ->
            mapOf(
                "title" to (action.title?.toString() ?: ""),
                "index" to (notification.actions?.indexOf(action) ?: 0),
            )
        } ?: emptyList()

        return mapOf(
            "id" to sbn.key,
            "packageName" to sbn.packageName,
            "appName" to appName,
            "title" to title,
            "body" to (bigText ?: text),
            "subText" to subText,
            "timestamp" to sbn.postTime,
            "icon" to iconBase64,
            "actions" to actions,
            "category" to notification.category,
            "isClearable" to sbn.isClearable,
        )
    }

    private fun extractIconBase64(sbn: StatusBarNotification): String? {
        try {
            val notification = sbn.notification
            val icon = notification.smallIcon ?: return null

            val drawable = icon.loadDrawable(applicationContext) ?: return null
            val bitmap = drawableToBitmap(drawable, 48) // 48x48 px icon

            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
            val bytes = stream.toByteArray()

            // Only send if reasonably small (< 10KB)
            if (bytes.size > 10240) return null

            return Base64.encodeToString(bytes, Base64.NO_WRAP)
        } catch (_: Exception) {
            return null
        }
    }

    private fun drawableToBitmap(drawable: Drawable, size: Int): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        }

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        return bitmap
    }
}
