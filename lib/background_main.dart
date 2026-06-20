import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_constants.dart';
import 'services/clipboard/clipboard_sync_service.dart';
import 'services/clipboard/native_clipboard_listener.dart';
import 'services/discovery/discovery_service.dart';
import 'services/network/network_service.dart';
import 'services/notification_sync/notification_sync_service.dart';
import 'services/persistent_connection/persistent_connection_service.dart';
import 'shared/models/device_model.dart';

/// Background Dart entrypoint that runs inside the foreground service's FlutterEngine.
/// This keeps discovery, clipboard sync, and persistent connections alive
/// even when the user swipes the app from recents.
///
/// Runs independently of the UI activity.
@pragma('vm:entry-point')
void backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  final service = _BackgroundService();
  await service.start();
}

class _BackgroundService {
  static const _serviceChannel = MethodChannel('com.svnate.sendate/foreground_service');
  static const _clipboardChannel = MethodChannel('com.svnate.sendate/native_clipboard');
  static const _notificationListenerChannel = MethodChannel('com.svnate.sendate/notification_listener');

  late DiscoveryService _discoveryService;
  late ClipboardSyncService _clipboardSyncService;
  late PersistentConnectionService _persistentConnectionService;
  late NotificationSyncService _notificationSyncService;
  final NetworkService _networkService = NetworkService();

  DeviceModel? _localDevice;
  String? _localIp;

  Future<void> start() async {
    // Initialize Hive for settings access
    await Hive.initFlutter();
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.devicesBox);
    await Hive.openBox(AppConstants.historyBox);

    // Load device identity from settings
    final settingsBox = Hive.box(AppConstants.settingsBox);
    final deviceId = settingsBox.get('device_id', defaultValue: 'unknown') as String;
    final deviceName = settingsBox.get('device_name', defaultValue: 'Android') as String;

    _localDevice = DeviceModel(
      id: deviceId,
      name: deviceName,
      deviceType: DeviceType.phone,
      fingerprint: deviceId,
    );

    // Get local IP
    _localIp = await _networkService.getLocalIp();

    // Initialize services
    _discoveryService = DiscoveryService();
    _clipboardSyncService = ClipboardSyncService();
    _persistentConnectionService = PersistentConnectionService();
    _persistentConnectionService.clipboardService = _clipboardSyncService;

    // Initialize notification sync service
    _notificationSyncService = NotificationSyncService();
    _notificationSyncService.initialize(
      deviceId: deviceId,
      deviceName: deviceName,
    );
    _persistentConnectionService.notificationSyncService = _notificationSyncService;

    // Set up method channel handlers
    _serviceChannel.setMethodCallHandler(_handleServiceCall);
    _clipboardChannel.setMethodCallHandler(_handleClipboardCall);
    _notificationListenerChannel.setMethodCallHandler(_handleNotificationListenerCall);

    // Start discovery
    await _discoveryService.start(_localDevice!, _localIp);

    // Start clipboard sync server
    _clipboardSyncService.startServer(AppConstants.transferPort);

    // Pre-populate known devices from Hive so auto-sync can fire immediately
    // even before UDP discovery finds the Mac/Windows device (2-5 s window).
    _ensureKnownDevicesFromHive();

    // Start auto-sync if enabled
    final autoSync = settingsBox.get('clipboard_auto_sync', defaultValue: false) as bool;
    if (autoSync) {
      _clipboardSyncService.startAutoSync();
    }

    // Start persistent connection server
    await _persistentConnectionService.start();

    // Start notification sync if enabled
    final notifSyncEnabled = settingsBox.get('notification_sync_enabled', defaultValue: true) as bool;
    if (notifSyncEnabled) {
      _notificationSyncService.startListening();
      _notificationSyncService.startServer(AppConstants.transferPort);
    }

    // Listen for discovered devices and update notification + auto-connect
    _discoveryService.devicesStream.listen((devices) {
      // Update known devices for clipboard fallback
      _clipboardSyncService.updateKnownDevices(devices);

      // Update known devices for notification sync fallback
      _notificationSyncService.updateKnownDevices(devices);

      // Auto-connect trusted devices
      final trustedIds = _getTrustedDeviceIds();
      for (final device in devices) {
        if (trustedIds.contains(device.id) && !_persistentConnectionService.isConnected(device.id)) {
          _persistentConnectionService.connectToDevice(device);
        }
      }

      // Update notification
      _updateNotification(devices.map((d) => d.name).toList());
    });

    // Notify native that the Dart background isolate is ready
    _serviceChannel.invokeMethod('serviceReady', null);

    // Signal ready with initial notification
    _updateNotification([]);
  }

  Future<dynamic> _handleServiceCall(MethodCall call) async {
    switch (call.method) {
      case 'onSendClipboard':
        debugPrint('[BackgroundService] onSendClipboard triggered from notification');
        // Ensure we have known devices from Hive (trusted devices with IPs)
        // This covers the case where background discovery hasn't found them yet
        _ensureKnownDevicesFromHive();
        // Read clipboard and broadcast to all known devices
        try {
          final text = await _clipboardSyncService.sendClipboardToAll();
          debugPrint('[BackgroundService] Clipboard send result: ${text != null ? "sent ${text.length} chars" : "empty/failed"}');
          return text != null;
        } catch (e) {
          debugPrint('[BackgroundService] Clipboard send error: $e');
          return false;
        }

      case 'updateClipboardAutoSync':
        // Main engine toggled clipboard auto-sync on/off in Settings.
        // Update background engine's clipboard service to match.
        final enabled = call.arguments as bool? ?? false;
        debugPrint('[BackgroundService] updateClipboardAutoSync: enabled=$enabled');
        if (enabled && !_clipboardSyncService.isAutoSyncEnabled) {
          _ensureKnownDevicesFromHive(); // make sure devices are loaded before starting
          _clipboardSyncService.startAutoSync();
          debugPrint('[BackgroundService] Auto-sync started from settings change');
        } else if (!enabled && _clipboardSyncService.isAutoSyncEnabled) {
          _clipboardSyncService.stopAutoSync();
          debugPrint('[BackgroundService] Auto-sync stopped from settings change');
        }
        return true;

      default:
        return null;
    }
  }

  /// Load trusted devices from Hive and update clipboard service's known devices list.
  /// This ensures the notification "Send Clipboard" button works even if
  /// background discovery hasn't found devices yet (the UI discovery did find them).
  void _ensureKnownDevicesFromHive() {
    try {
      final box = Hive.box(AppConstants.devicesBox);
      final devices = <DeviceModel>[];

      // TrustedDevicesNotifier stores each device by its ID as the key
      // Each value is a Map with 'id', 'name', 'ipAddress', 'port', etc.
      for (final key in box.keys) {
        final item = box.get(key);
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final ip = map['ipAddress'] as String?;
        final id = map['id'] as String? ?? '';
        if (ip == null || ip.isEmpty || id.isEmpty) continue;
        devices.add(DeviceModel(
          id: id,
          name: map['name'] as String? ?? 'Unknown',
          deviceType: DeviceType.unknown,
          fingerprint: '',
          ipAddress: ip,
          port: map['port'] as int?,
        ));
      }

      if (devices.isNotEmpty) {
        _clipboardSyncService.updateKnownDevices(devices);
        debugPrint('[BackgroundService] Loaded ${devices.length} trusted device(s) from Hive for clipboard');
      } else {
        debugPrint('[BackgroundService] No trusted devices with IP found in Hive');
      }
    } catch (e) {
      debugPrint('[BackgroundService] Error loading devices from Hive: $e');
    }
  }

  Future<dynamic> _handleClipboardCall(MethodCall call) async {
    // This handles clipboard methods from the native side for the background engine
    switch (call.method) {
      case 'onClipboardChanged':
        final text = call.arguments as String? ?? '';
        if (text.isNotEmpty && _clipboardSyncService.isAutoSyncEnabled) {
          // The native clipboard listener detected a change, broadcast it
          _clipboardSyncService.onLocalClipboardChanged(text);
        }
        return null;
      default:
        return null;
    }
  }

  Future<dynamic> _handleNotificationListenerCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationPosted':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        // Add source device info and broadcast
        data['sourceDeviceId'] = _localDevice?.id ?? '';
        data['sourceDeviceName'] = _localDevice?.name ?? '';
        _notificationSyncService.onLocalNotificationPosted(data);
        return null;

      case 'onNotificationRemoved':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final id = data['id'] as String? ?? '';
        if (id.isNotEmpty) {
          _notificationSyncService.onLocalNotificationRemoved(id);
        }
        return null;

      case 'isPermissionGranted':
        return _notificationSyncService.isPermissionGranted();

      case 'openPermissionSettings':
        await _notificationSyncService.openPermissionSettings();
        return true;

      default:
        return null;
    }
  }

  void _updateNotification(List<String> deviceNames) {
    if (deviceNames.isEmpty) {
      _serviceChannel.invokeMethod('updateNotification', {
        'title': 'Sendate',
        'body': 'Searching for devices...',
        'devices': <String>[],
      });
    } else if (deviceNames.length == 1) {
      _serviceChannel.invokeMethod('updateNotification', {
        'title': 'Sendate',
        'body': 'Connected to: ${deviceNames.first}',
        'devices': deviceNames,
      });
    } else {
      _serviceChannel.invokeMethod('updateNotification', {
        'title': 'Sendate',
        'body': 'Connected to ${deviceNames.length} devices',
        'devices': deviceNames,
      });
    }
  }

  List<String> _getTrustedDeviceIds() {
    try {
      final box = Hive.box(AppConstants.devicesBox);
      // Devices are stored individually by their ID as key
      return box.keys
          .map((key) => key.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[BackgroundMain] Failed to load trusted device IDs: $e');
      return [];
    }
  }
}
