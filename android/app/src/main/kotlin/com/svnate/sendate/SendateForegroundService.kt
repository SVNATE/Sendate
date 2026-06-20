package com.svnate.sendate

import android.app.*
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Persistent foreground service.
 *
 * CRITICAL: This service maintains its own FlutterEngine so that
 * discovery, clipboard sync, and transfers keep running even when
 * the user swipes the app from recents (killing the main activity).
 *
 * Architecture:
 * - The service starts a headless FlutterEngine running `backgroundMain()`
 * - This Dart isolate runs discovery, clipboard, and transfer servers
 * - The main activity communicates with it via method channels
 * - When the activity is killed, the service keeps running independently
 */
class SendateForegroundService : Service() {

    companion object {
        private const val TAG = "SendateFGService"
        const val CHANNEL_ID = "sendate_foreground_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.svnate.sendate.ACTION_STOP"
        const val SERVICE_CHANNEL_NAME = "com.svnate.sendate/foreground_service"
        const val CLIPBOARD_CHANNEL_NAME = "com.svnate.sendate/native_clipboard"
        const val NOTIFICATION_LISTENER_CHANNEL_NAME = "com.svnate.sendate/notification_listener"

        private var instance: SendateForegroundService? = null

        fun isRunning(): Boolean = instance != null

        /**
         * Called from MainActivity to update the foreground notification
         * when the main UI discovers devices.
         */
        fun updateNotificationFromUI(context: Context, title: String, body: String, deviceNames: List<String>) {
            val svc = instance
            if (svc != null) {
                svc.updateForegroundNotification(title, body, deviceNames)
            } else {
                // Service not running yet, update directly via NotificationManager
                try {
                    val openIntent = Intent(context, context.javaClass)
                    openIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    val openPendingIntent = PendingIntent.getActivity(
                        context, 0, openIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )

                    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                        .setSmallIcon(R.drawable.ic_notification)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setContentIntent(openPendingIntent)
                        .setOngoing(true)
                        .setSilent(true)
                        .setShowWhen(false)
                        .setPriority(NotificationCompat.PRIORITY_LOW)

                    if (deviceNames.isNotEmpty()) {
                        // Use getActivity() for the same reasons as buildNotification()
                        val clipboardIntent = Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("notification_action", "send_clipboard")
                        }
                        val clipboardPendingIntent = PendingIntent.getActivity(
                            context, 2, clipboardIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        builder.addAction(android.R.drawable.ic_menu_share, "Send Clipboard", clipboardPendingIntent)
                    }

                    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, builder.build())
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to update notification from UI: ${e.message}")
                }
            }
        }
    }

    private var backgroundEngine: FlutterEngine? = null
    private var serviceChannel: MethodChannel? = null
    private var clipboardChannel: MethodChannel? = null
    private var notificationListenerChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var connectedDeviceNames: List<String> = emptyList()

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")

        when (intent?.action) {
            ACTION_STOP -> {
                Log.d(TAG, "Stopping service")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // Start as foreground with notification
        try {
            val notification = buildNotification("Sendate", "Searching for devices...", emptyList())

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "startForeground called successfully")

            acquireWakeLock()
            startBackgroundEngine()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground: ${e.message}", e)
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "Service onDestroy")
        releaseWakeLock()
        backgroundEngine?.destroy()
        backgroundEngine = null
        instance = null
        super.onDestroy()
    }

    /**
     * Start a headless Flutter engine running the background Dart entrypoint.
     * This keeps discovery and clipboard sync alive even when the main activity is killed.
     */
    private fun startBackgroundEngine() {
        if (backgroundEngine != null) {
            Log.d(TAG, "Background engine already running")
            return
        }

        try {
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            flutterLoader.ensureInitializationComplete(applicationContext, null)

            backgroundEngine = FlutterEngine(applicationContext).also { engine ->
                // Execute the background Dart entrypoint
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        flutterLoader.findAppBundlePath(),
                        "backgroundMain"
                    )
                )

                // Set up service method channel on the background engine
                serviceChannel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    SERVICE_CHANNEL_NAME
                )

                serviceChannel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "serviceReady" -> {
                            Log.d(TAG, "Background Dart isolate is ready")
                            result.success(true)
                        }
                        "updateNotification" -> {
                            val title = call.argument<String>("title") ?: "Sendate"
                            val body = call.argument<String>("body") ?: "Running..."
                            val devices = call.argument<List<String>>("devices") ?: emptyList()
                            updateForegroundNotification(title, body, devices)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }

                // Set up clipboard channel on the background engine
                clipboardChannel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    CLIPBOARD_CHANNEL_NAME
                )

                val clipboardManager = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager

                clipboardManager.addPrimaryClipChangedListener {
                    try {
                        val text = clipboardManager.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                        if (text.isNotEmpty()) {
                            clipboardChannel?.invokeMethod("onClipboardChanged", text)
                        }
                    } catch (_: Exception) {}
                }

                clipboardChannel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setClipboard" -> {
                            val text = call.arguments as? String ?: ""
                            val clip = ClipData.newPlainText("Sendate", text)
                            clipboardManager.setPrimaryClip(clip)
                            result.success(true)
                        }
                        "getClipboard" -> {
                            val text = clipboardManager.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                            result.success(text)
                        }
                        else -> result.notImplemented()
                    }
                }

                // Set up notification listener channel on the background engine
                notificationListenerChannel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    NOTIFICATION_LISTENER_CHANNEL_NAME
                )

                notificationListenerChannel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "isPermissionGranted" -> {
                            result.success(SendateNotificationListener.isPermissionGranted(applicationContext))
                        }
                        "openPermissionSettings" -> {
                            SendateNotificationListener.openPermissionSettings(applicationContext)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                }

                // Register the MethodChannel with the NotificationListener service
                SendateNotificationListener.setMethodChannel(notificationListenerChannel!!)
            }

            Log.d(TAG, "Background FlutterEngine started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background engine: ${e.message}", e)
        }
    }

    fun updateForegroundNotification(title: String, body: String, deviceNames: List<String>) {
        connectedDeviceNames = deviceNames
        try {
            val notification = buildNotification(title, body, deviceNames)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, notification)
            Log.d(TAG, "Notification updated: $body")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update notification: ${e.message}", e)
        }
    }

    private fun buildNotification(title: String, body: String, deviceNames: List<String>): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        openIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val openPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(openPendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        // Action buttons only when devices are connected.
        // IMPORTANT: Use PendingIntent.getActivity() (not getService()) for both buttons.
        // Reason 1: Android 10+ blocks background services from reading the clipboard
        //           (getPrimaryClip() returns null). The Activity has foreground focus,
        //           so clipboard reads succeed when launched via getActivity().
        // Reason 2: Android 10+ blocks background services from starting Activities via
        //           startActivity(). PendingIntent.getActivity() tapped by the user is
        //           an explicitly allowed exemption from that restriction.
        if (deviceNames.isNotEmpty()) {
            val clipboardIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("notification_action", "send_clipboard")
            }
            val clipboardPendingIntent = PendingIntent.getActivity(
                this, 2, clipboardIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(android.R.drawable.ic_menu_share, "Send Clipboard", clipboardPendingIntent)

            val filesIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("notification_action", "pick_files")
            }
            val filesPendingIntent = PendingIntent.getActivity(
                this, 3, filesIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(android.R.drawable.ic_menu_upload, "Send Files", filesPendingIntent)
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sendate Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Sendate running for device discovery, clipboard sync, and file transfer"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Sendate::ForegroundServiceWakeLock"
            ).apply { acquire(Long.MAX_VALUE) }
            Log.d(TAG, "Wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Wake lock error: ${e.message}", e)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
