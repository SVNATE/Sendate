import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/models/device_model.dart';

/// Represents a captured notification from the Android phone.
class SyncedNotification {
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String body;
  final String? subText;
  final int timestamp;
  final String? iconBase64;
  final List<NotificationAction> actions;
  final String? category;
  final bool isClearable;
  final String sourceDeviceId;
  final String sourceDeviceName;

  SyncedNotification({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.body,
    this.subText,
    required this.timestamp,
    this.iconBase64,
    this.actions = const [],
    this.category,
    this.isClearable = true,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'packageName': packageName,
        'appName': appName,
        'title': title,
        'body': body,
        'subText': subText,
        'timestamp': timestamp,
        'icon': iconBase64,
        'actions': actions.map((a) => a.toJson()).toList(),
        'category': category,
        'isClearable': isClearable,
        'sourceDeviceId': sourceDeviceId,
        'sourceDeviceName': sourceDeviceName,
      };

  factory SyncedNotification.fromJson(Map<String, dynamic> json) {
    return SyncedNotification(
      id: json['id'] as String? ?? '',
      packageName: json['packageName'] as String? ?? '',
      appName: json['appName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      subText: json['subText'] as String?,
      timestamp: json['timestamp'] as int? ?? 0,
      iconBase64: json['icon'] as String?,
      actions: (json['actions'] as List<dynamic>?)
              ?.map((a) => NotificationAction.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      category: json['category'] as String?,
      isClearable: json['isClearable'] as bool? ?? true,
      sourceDeviceId: json['sourceDeviceId'] as String? ?? '',
      sourceDeviceName: json['sourceDeviceName'] as String? ?? '',
    );
  }
}

class NotificationAction {
  final String title;
  final int index;

  NotificationAction({required this.title, required this.index});

  Map<String, dynamic> toJson() => {'title': title, 'index': index};

  factory NotificationAction.fromJson(Map<String, dynamic> json) {
    return NotificationAction(
      title: json['title'] as String? ?? '',
      index: json['index'] as int? ?? 0,
    );
  }
}

/// Service that captures Android notifications and syncs them to connected devices.
/// On the receiving end, it displays incoming notifications from remote devices.
///
/// Architecture:
/// - On Android (sender): listens via NotificationListenerService → MethodChannel → broadcasts over TCP
/// - On Desktop (receiver): receives notification messages → shows local notification or in-app UI
class NotificationSyncService {
  static const _notificationChannel =
      MethodChannel('com.svnate.sendate/notification_listener');

  final _receivedNotificationsController =
      StreamController<SyncedNotification>.broadcast();
  final _removedNotificationsController = StreamController<String>.broadcast();

  final List<Socket> _connectedSockets = [];
  final List<DeviceModel> _knownDevices = [];

  bool _isEnabled = false;
  bool _isListenerActive = false;
  String _localDeviceId = '';
  String _localDeviceName = '';

  /// Stream of notifications received from remote devices
  Stream<SyncedNotification> get receivedNotifications =>
      _receivedNotificationsController.stream;

  /// Stream of notification IDs removed on remote devices
  Stream<String> get removedNotifications =>
      _removedNotificationsController.stream;

  bool get isEnabled => _isEnabled;
  bool get isListenerActive => _isListenerActive;

  /// Initialize the service with local device info
  void initialize({required String deviceId, required String deviceName}) {
    _localDeviceId = deviceId;
    _localDeviceName = deviceName;
  }

  /// Start listening for local notifications (Android only) and broadcasting them
  void startListening() {
    if (!Platform.isAndroid) return;

    _isEnabled = true;

    // Set up method channel handler for notifications from native
    _notificationChannel.setMethodCallHandler(_handleNativeCall);

    debugPrint('[NotificationSync] Listener started');
  }

  /// Stop listening for notifications
  void stopListening() {
    _isEnabled = false;
    _notificationChannel.setMethodCallHandler(null);
    debugPrint('[NotificationSync] Listener stopped');
  }

  /// Check if notification listener permission is granted (Android only)
  Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _notificationChannel.invokeMethod<bool>('isPermissionGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open system settings to grant notification listener permission
  Future<void> openPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _notificationChannel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  /// Register a connected device socket for forwarding notifications
  void addConnectedSocket(Socket socket) {
    _connectedSockets.add(socket);
  }

  /// Remove a disconnected device socket
  void removeConnectedSocket(Socket socket) {
    _connectedSockets.remove(socket);
  }

  /// Update known devices for TCP fallback
  void updateKnownDevices(List<DeviceModel> devices) {
    _knownDevices.clear();
    _knownDevices.addAll(devices.where((d) => d.ipAddress != null));
  }

  /// Handle incoming notification from a remote device (received via persistent connection)
  void onRemoteNotificationReceived(Map<String, dynamic> data) {
    try {
      final notification = SyncedNotification.fromJson(data);
      _receivedNotificationsController.add(notification);

      // Save to history
      _saveToHistory(notification);

      debugPrint(
          '[NotificationSync] Received: ${notification.appName} - ${notification.title}');
    } catch (e) {
      debugPrint('[NotificationSync] Error parsing remote notification: $e');
    }
  }

  /// Handle notification removal from a remote device
  void onRemoteNotificationRemoved(String notificationId) {
    _removedNotificationsController.add(notificationId);
  }

  /// Handle calls from the native NotificationListenerService
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (!_isEnabled) return null;

    switch (call.method) {
      case 'onNotificationPosted':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        onLocalNotificationPosted(data);
        return null;

      case 'onNotificationRemoved':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final id = data['id'] as String? ?? '';
        onLocalNotificationRemoved(id);
        return null;

      default:
        return null;
    }
  }

  /// Called when a new notification appears on this device — broadcast to connected devices
  void onLocalNotificationPosted(Map<String, dynamic> data) {
    if (!_isEnabled) return;

    // Add source device info if not already present
    data['sourceDeviceId'] ??= _localDeviceId;
    data['sourceDeviceName'] ??= _localDeviceName;

    // Broadcast to all connected devices
    _broadcastNotification(data);

    debugPrint(
        '[NotificationSync] Broadcasting: ${data['appName']} - ${data['title']}');
  }

  /// Called when a notification is removed on this device
  void onLocalNotificationRemoved(String notificationId) {
    if (!_isEnabled) return;

    final message = jsonEncode({
      'type': 'notification_removed',
      'id': notificationId,
      'sourceDeviceId': _localDeviceId,
    });

    _broadcastRaw(message);
  }

  /// Broadcast notification data to all connected sockets
  void _broadcastNotification(Map<String, dynamic> data) {
    final message = jsonEncode({
      'type': 'notification',
      ...data,
    });

    _broadcastRaw(message);
  }

  /// Send raw message string to all connected sockets
  void _broadcastRaw(String message) {
    final encoded = '$message\n';
    final bytes = utf8.encode(encoded);

    for (final socket in List.of(_connectedSockets)) {
      try {
        socket.add(bytes);
      } catch (_) {
        // Socket likely disconnected, will be cleaned up by connection service
      }
    }

    // Also send via TCP fallback to known devices that aren't in socket list
    _sendViaFallback(message);
  }

  /// TCP fallback for devices discovered but not connected via persistent socket
  Future<void> _sendViaFallback(String message) async {
    for (final device in _knownDevices) {
      if (device.ipAddress == null) continue;

      try {
        final socket = await Socket.connect(
          device.ipAddress!,
          AppConstants.transferPort + 3, // Notification-specific port
          timeout: const Duration(seconds: 3),
        );
        socket.add(utf8.encode('$message\n'));
        await socket.flush();
        await socket.close();
      } catch (_) {
        // Device unreachable via fallback — not critical
      }
    }
  }

  /// Start a TCP server to receive notifications from remote devices
  Future<ServerSocket?> startServer(int port) async {
    try {
      final server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port + 3, // transferPort + 3 = notification port
      );
      server.listen(_handleIncomingConnection);
      debugPrint('[NotificationSync] Server listening on port ${port + 3}');
      return server;
    } catch (e) {
      debugPrint('[NotificationSync] Failed to start server: $e');
      return null;
    }
  }

  void _handleIncomingConnection(Socket socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        final str = buffer.toString();
        if (str.contains('\n')) {
          final lines = str.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            _processIncomingMessage(line);
          }
          buffer.clear();
        }
      },
      onDone: () => socket.destroy(),
      onError: (_) => socket.destroy(),
    );
  }

  void _processIncomingMessage(String message) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'notification':
          onRemoteNotificationReceived(json);
        case 'notification_removed':
          final id = json['id'] as String? ?? '';
          onRemoteNotificationRemoved(id);
      }
    } catch (_) {}
  }

  void _saveToHistory(SyncedNotification notification) {
    try {
      final box = Hive.box(AppConstants.historyBox);
      box.put('notif_${notification.timestamp}', {
        'id': notification.id,
        'type': 'notification',
        'appName': notification.appName,
        'title': notification.title,
        'body': notification.body,
        'deviceName': notification.sourceDeviceName,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(notification.timestamp)
            .toIso8601String(),
      });
    } catch (_) {}
  }

  void dispose() {
    stopListening();
    _receivedNotificationsController.close();
    _removedNotificationsController.close();
  }
}
