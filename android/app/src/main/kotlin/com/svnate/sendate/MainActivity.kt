package com.svnate.sendate

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "SendateMain"
        private const val NOTIFICATION_PERMISSION_CODE = 1001
    }

    private val BT_CHANNEL = "com.svnate.sendate/bluetooth"
    private val WFD_CHANNEL = "com.svnate.sendate/wifi_direct"
    private val CLIPBOARD_CHANNEL = "com.svnate.sendate/native_clipboard"
    private val SERVICE_CHANNEL = "com.svnate.sendate/foreground_service"
    private val NOTIFICATION_LISTENER_CHANNEL = "com.svnate.sendate/notification_listener"

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var clipboardChannel: MethodChannel? = null
    private var btChannel: MethodChannel? = null
    private var wfdChannel: MethodChannel? = null
    private var serviceChannel: MethodChannel? = null
    private var notificationListenerChannel: MethodChannel? = null

    private var wifiP2pManager: WifiP2pManager? = null
    private var wifiP2pChannel: WifiP2pManager.Channel? = null

    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    device?.let {
                        try {
                            btChannel?.invokeMethod("onDeviceFound", mapOf(
                                "name" to (it.name ?: "Unknown"),
                                "address" to it.address
                            ))
                        } catch (_: SecurityException) {}
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    btChannel?.invokeMethod("onScanFinished", null)
                }
            }
        }
    }

    private val wfdReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    try {
                        wifiP2pManager?.requestPeers(wifiP2pChannel) { peers ->
                            val deviceList = peers.deviceList.map { device ->
                                mapOf("name" to device.deviceName, "address" to device.deviceAddress)
                            }
                            wfdChannel?.invokeMethod("onPeersFound", deviceList)
                        }
                    } catch (_: SecurityException) {}
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    wifiP2pManager?.requestConnectionInfo(wifiP2pChannel) { info ->
                        if (info.groupFormed) {
                            wfdChannel?.invokeMethod("onConnected", mapOf(
                                "groupOwnerAddress" to info.groupOwnerAddress?.hostAddress,
                                "isGroupOwner" to info.isGroupOwner
                            ))
                        } else {
                            wfdChannel?.invokeMethod("onDisconnected", null)
                        }
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- Foreground Service Channel (for the main UI to control the service) ---
        serviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
        serviceChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    requestNotificationPermissionAndStartService()
                    result.success(true)
                }
                "stopService" -> {
                    stopSendateService()
                    result.success(true)
                }
                "isRunning" -> {
                    result.success(SendateForegroundService.isRunning())
                }
                "getPendingAction" -> {
                    // Check stored pending action first, then intent extra
                    val action = pendingNotificationAction
                        ?: intent?.getStringExtra("notification_action")
                    pendingNotificationAction = null
                    intent?.removeExtra("notification_action")
                    result.success(action)
                }
                "updateNotification" -> {
                    // Forward notification update to the running foreground service
                    val title = call.argument<String>("title") ?: "Sendate"
                    val body = call.argument<String>("body") ?: "Running..."
                    val devices = call.argument<List<String>>("devices") ?: emptyList()
                    SendateForegroundService.updateNotificationFromUI(this, title, body, devices)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // --- Native Clipboard Listener (for the main UI engine) ---
        clipboardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
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
                    val clip = android.content.ClipData.newPlainText("Sendate", text)
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

        // --- Bluetooth ---
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        btChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL)
        btChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(bluetoothAdapter != null && bluetoothAdapter!!.isEnabled)
                "startScan" -> {
                    try {
                        val filter = IntentFilter().apply {
                            addAction(BluetoothDevice.ACTION_FOUND)
                            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
                        }
                        registerReceiver(btReceiver, filter)
                        bluetoothAdapter?.startDiscovery()
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.error("PERMISSION", "Bluetooth permission denied", null)
                    }
                }
                "stopScan" -> {
                    try { bluetoothAdapter?.cancelDiscovery(); unregisterReceiver(btReceiver) } catch (_: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // --- WiFi Direct ---
        wifiP2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        wifiP2pChannel = wifiP2pManager?.initialize(this, Looper.getMainLooper(), null)

        wfdChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WFD_CHANNEL)
        wfdChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(wifiP2pManager != null)
                "startDiscovery" -> {
                    try {
                        val filter = IntentFilter().apply {
                            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                        }
                        registerReceiver(wfdReceiver, filter)
                        wifiP2pManager?.discoverPeers(wifiP2pChannel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { result.success(true) }
                            override fun onFailure(reason: Int) { result.error("FAILED", "Discovery failed: $reason", null) }
                        })
                    } catch (e: SecurityException) {
                        result.error("PERMISSION", "WiFi Direct permission denied", null)
                    }
                }
                "stopDiscovery" -> {
                    try { wifiP2pManager?.stopPeerDiscovery(wifiP2pChannel, null); unregisterReceiver(wfdReceiver) } catch (_: Exception) {}
                    result.success(true)
                }
                "connect" -> {
                    val address = call.argument<String>("address") ?: ""
                    val config = WifiP2pConfig().apply { deviceAddress = address }
                    try {
                        wifiP2pManager?.connect(wifiP2pChannel, config, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { result.success(true) }
                            override fun onFailure(reason: Int) { result.error("FAILED", "Connect failed: $reason", null) }
                        })
                    } catch (e: SecurityException) { result.error("PERMISSION", "Permission denied", null) }
                }
                "disconnect" -> { wifiP2pManager?.removeGroup(wifiP2pChannel, null); result.success(true) }
                else -> result.notImplemented()
            }
        }

        // --- Notification Listener Channel (for checking permission from UI) ---
        notificationListenerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_LISTENER_CHANNEL)
        notificationListenerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> {
                    result.success(SendateNotificationListener.isPermissionGranted(this))
                }
                "openPermissionSettings" -> {
                    SendateNotificationListener.openPermissionSettings(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Auto-start the foreground service
        requestNotificationPermissionAndStartService()
    }

    private var pendingNotificationAction: String? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Update the activity's intent so getPendingAction can read it
        // Handle notification action when activity is brought back
        val action = intent.getStringExtra("notification_action")
        if (action != null) {
            Log.d(TAG, "onNewIntent with action: $action")
            if (serviceChannel != null) {
                serviceChannel?.invokeMethod("onNotificationAction", action)
            } else {
                // Flutter engine not ready yet — store for later retrieval via getPendingAction
                pendingNotificationAction = action
            }
            intent.removeExtra("notification_action")
        }
    }

    private fun requestNotificationPermissionAndStartService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                Log.d(TAG, "Requesting POST_NOTIFICATIONS permission")
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
                return
            }
        }
        startSendateService()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "POST_NOTIFICATIONS granted")
            } else {
                Log.w(TAG, "POST_NOTIFICATIONS denied")
            }
            startSendateService()
        }
    }

    private fun startSendateService() {
        try {
            val intent = Intent(this, SendateForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d(TAG, "Foreground service start requested")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service: ${e.message}", e)
        }
    }

    private fun stopSendateService() {
        try {
            stopService(Intent(this, SendateForegroundService::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop service: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(btReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(wfdReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }
}
