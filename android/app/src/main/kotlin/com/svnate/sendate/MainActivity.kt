package com.svnate.sendate

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
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
import android.net.wifi.WifiManager
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "SendateMain"
        private const val NOTIFICATION_PERMISSION_CODE = 1001
    }

    private val BT_CHANNEL = "com.svnate.sendate/bluetooth"
    private val BT_TRANSFER_CHANNEL = "com.svnate.sendate/bt_transfer"
    private val WFD_CHANNEL = "com.svnate.sendate/wifi_direct"
    private val CLIPBOARD_CHANNEL = "com.svnate.sendate/native_clipboard"
    private val SERVICE_CHANNEL = "com.svnate.sendate/foreground_service"
    private val NOTIFICATION_LISTENER_CHANNEL = "com.svnate.sendate/notification_listener"
    private val OPEN_FILES_CHANNEL = "com.svnate.sendate/open_files"
    private val MULTICAST_CHANNEL = "com.svnate.sendate/multicast"

    private val BT_SPP_UUID: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB") // Standard SPP UUID

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var clipboardChannel: MethodChannel? = null
    private var btChannel: MethodChannel? = null
    private var btTransferChannel: MethodChannel? = null
    private var btClientSocket: BluetoothSocket? = null
    private var btServerSocket: BluetoothServerSocket? = null
    private var btServerThread: Thread? = null
    private var wfdChannel: MethodChannel? = null
    private var serviceChannel: MethodChannel? = null
    private var notificationListenerChannel: MethodChannel? = null

    private var wifiP2pManager: WifiP2pManager? = null
    private var wifiP2pChannel: WifiP2pManager.Channel? = null
    private var openFilesChannel: MethodChannel? = null
    private var multicastChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null

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
                "updateClipboardAutoSync" -> {
                    // Settings toggle in main UI — forward to background engine so it
                    // can start/stop its own ClipboardSyncService.startAutoSync()
                    val enabled = call.arguments as? Boolean ?: false
                    SendateForegroundService.forwardClipboardAutoSync(enabled)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // --- Native Clipboard Listener (for the main UI engine) ---
        clipboardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_CHANNEL)
        val clipboardManager = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        this.clipboardManager = clipboardManager // Store for onNewIntent clipboard pre-read

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

        // --- Multicast Lock ---
        multicastChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MULTICAST_CHANNEL)
        multicastChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    if (multicastLock == null) {
                        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                        multicastLock = wifiManager?.createMulticastLock("SendateMulticastLock")
                        multicastLock?.setReferenceCounted(true)
                    }
                    multicastLock?.let {
                        if (!it.isHeld) it.acquire()
                    }
                    result.success(true)
                }
                "release" -> {
                    multicastLock?.let {
                        if (it.isHeld) it.release()
                    }
                    result.success(true)
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

        // --- Bluetooth RFCOMM File Transfer ---
        btTransferChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_TRANSFER_CHANNEL)
        btTransferChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Connect as RFCOMM client to a paired device
                "connect" -> {
                    val address = call.argument<String>("address") ?: run {
                        result.error("ARG", "address required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val device = bluetoothAdapter?.getRemoteDevice(address)
                                ?: throw IOException("Device not found")
                            bluetoothAdapter?.cancelDiscovery()
                            val socket = device.createRfcommSocketToServiceRecord(BT_SPP_UUID)
                            socket.connect()
                            btClientSocket?.close()
                            btClientSocket = socket
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("CONNECT_FAIL", e.message, null)
                            }
                        }
                    }.start()
                }
                // Send raw bytes over the established RFCOMM socket
                "send" -> {
                    val socket = btClientSocket ?: run {
                        result.error("NO_SOCKET", "Not connected", null); return@setMethodCallHandler
                    }
                    val data = call.argument<ByteArray>("data") ?: run {
                        result.error("ARG", "data required", null); return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            socket.outputStream.write(data)
                            socket.outputStream.flush()
                            runOnUiThread { result.success(true) }
                        } catch (e: IOException) {
                            runOnUiThread { result.error("SEND_FAIL", e.message, null) }
                        }
                    }.start()
                }
                // Disconnect client socket
                "disconnect" -> {
                    try { btClientSocket?.close() } catch (_: IOException) {}
                    btClientSocket = null
                    result.success(true)
                }
                // Start RFCOMM server socket to accept incoming connections
                "startServer" -> {
                    btServerThread?.interrupt()
                    btServerThread = Thread {
                        try {
                            btServerSocket?.close()
                            btServerSocket = bluetoothAdapter
                                ?.listenUsingRfcommWithServiceRecord("Sendate", BT_SPP_UUID)
                            Log.d(TAG, "BT server listening…")
                            while (!Thread.currentThread().isInterrupted) {
                                val clientSocket = btServerSocket?.accept() ?: break
                                // Read all data from the incoming client
                                Thread {
                                    _handleIncomingBtClient(clientSocket)
                                }.start()
                            }
                        } catch (_: IOException) { /* server closed */ }
                    }
                    btServerThread?.start()
                    result.success(true)
                }
                // Stop the RFCOMM server
                "stopServer" -> {
                    btServerThread?.interrupt()
                    btServerThread = null
                    try { btServerSocket?.close() } catch (_: IOException) {}
                    btServerSocket = null
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
                // Return the group owner's IP address (needed for the non-owner to connect via TCP)
                "getGroupInfo" -> {
                    try {
                        wifiP2pManager?.requestGroupInfo(wifiP2pChannel) { group ->
                            if (group != null) {
                                result.success(mapOf(
                                    "groupOwnerAddress" to group.owner.deviceAddress,
                                    "networkName" to group.networkName,
                                    "passphrase" to group.passphrase,
                                ))
                            } else {
                                result.error("NO_GROUP", "No active Wi-Fi Direct group", null)
                            }
                        }
                    } catch (e: SecurityException) {
                        result.error("PERMISSION", "Permission denied", null)
                    }
                }
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
                "performAction" -> {
                    val notifId = call.argument<String>("notificationId") ?: ""
                    val actionIndex = call.argument<Int>("actionIndex") ?: 0
                    SendateNotificationListener.performNotificationAction(notifId, actionIndex)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Auto-start the foreground service
        requestNotificationPermissionAndStartService()

        // Register the open-files channel (used by share_handler and direct VIEW intents)
        openFilesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_FILES_CHANNEL)

        // Flush any files that arrived before the engine was ready
        pendingSharedFiles?.let { files ->
            pendingSharedFiles = null
            openFilesChannel?.invokeMethod("openFiles", files)
        }

        // Handle share / VIEW intent that launched the app cold
        handleIncomingIntent(intent)
    }

    private var pendingNotificationAction: String? = null
    private var pendingSharedFiles: List<String>? = null
    private var clipboardManager: ClipboardManager? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // Update the activity's intent so getPendingAction can read it
        // Handle notification action when activity is brought back
        val action = intent.getStringExtra("notification_action")
        if (action != null) {
            Log.d(TAG, "onNewIntent with action: $action")
            if (serviceChannel != null) {
                if (action == "send_clipboard") {
                    val clipText = try {
                        clipboardManager?.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
                    } catch (e: Exception) {
                        Log.w(TAG, "Clipboard read in onNewIntent failed: ${e.message}")
                        ""
                    }
                    Log.d(TAG, "onNewIntent send_clipboard: clipText.length=${clipText.length}")
                    serviceChannel?.invokeMethod("onSendClipboardFromNotification", clipText)
                } else {
                    serviceChannel?.invokeMethod("onNotificationAction", action)
                }
            } else {
                pendingNotificationAction = action
            }
            intent.removeExtra("notification_action")
        }

        // Handle share / VIEW intent delivered while app is already running
        handleIncomingIntent(intent)
    }

    /// Resolve a share/VIEW intent to a list of real file paths and forward to Flutter.
    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val intentAction = intent.action ?: return

        val uris = mutableListOf<Uri>()

        when (intentAction) {
            Intent.ACTION_SEND -> {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (uri != null) uris.add(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                }
                if (list != null) uris.addAll(list)
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null) uris.add(uri)
            }
            else -> return
        }

        if (uris.isEmpty()) return

        val paths = uris.mapNotNull { uri -> resolveUriToPath(uri) }
        if (paths.isEmpty()) return

        Log.d(TAG, "handleIncomingIntent: forwarding ${paths.size} file(s) to Flutter")
        if (openFilesChannel != null) {
            openFilesChannel?.invokeMethod("openFiles", paths)
        } else {
            // Flutter engine not ready yet — store for later
            pendingSharedFiles = paths
        }
    }

    /// Copy a content:// URI to a temp file and return its absolute path.
    private fun resolveUriToPath(uri: Uri): String? {
        return try {
            val cursor = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
            val fileName = cursor?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: "shared_file_${System.currentTimeMillis()}"

            val tempDir = File(cacheDir, "sendate_shared").apply { mkdirs() }
            val tempFile = File(tempDir, fileName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output -> input.copyTo(output) }
            }
            tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve URI $uri: ${e.message}")
            null
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
        try { btClientSocket?.close() } catch (_: IOException) {}
        try { btServerSocket?.close() } catch (_: IOException) {}
        btServerThread?.interrupt()
        super.onDestroy()
    }

    /// Handle bytes received from an incoming Bluetooth client connection.
    private fun _handleIncomingBtClient(socket: BluetoothSocket) {
        try {
            val inputStream = socket.inputStream
            val buffer = ByteArray(16384)
            val accumulated = mutableListOf<Byte>()

            while (true) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead < 0) break
                accumulated.addAll(buffer.take(bytesRead).toList())
            }

            val data = accumulated.toByteArray()
            Log.d(TAG, "BT received ${data.size} bytes")
            runOnUiThread {
                btTransferChannel?.invokeMethod("onDataReceived",
                    mapOf("data" to data, "address" to socket.remoteDevice.address))
            }
        } catch (e: IOException) {
            Log.e(TAG, "BT client read error: ${e.message}")
        } finally {
            try { socket.close() } catch (_: IOException) {}
        }
    }
}
