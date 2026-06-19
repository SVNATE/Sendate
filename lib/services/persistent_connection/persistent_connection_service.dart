import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../clipboard/clipboard_sync_service.dart';
import '../notification_sync/notification_sync_service.dart';

enum ConnectionState { disconnected, connecting, connected, reconnecting }

class DeviceConnection {
  final DeviceModel device;
  ConnectionState state;
  Socket? socket;
  DateTime? connectedSince;
  int reconnectAttempts;

  DeviceConnection({
    required this.device,
    this.state = ConnectionState.disconnected,
    this.socket,
    this.connectedSince,
    this.reconnectAttempts = 0,
  });
}

/// Maintains persistent TCP connections to trusted devices.
/// Handles heartbeat, auto-reconnect, and routes clipboard/message data.
class PersistentConnectionService {
  final _log = const AppLogger('PersistentConn');
  final Map<String, DeviceConnection> _connections = {};
  final _stateController = StreamController<Map<String, DeviceConnection>>.broadcast();
  Timer? _heartbeatTimer;
  ServerSocket? _server;
  bool _isRunning = false;
  ClipboardSyncService? clipboardService;

  static const _heartbeatInterval = Duration(seconds: 5);
  static const _maxReconnectAttempts = 10;
  static const _persistentPort = 53320; // Dedicated port for persistent connections

  Stream<Map<String, DeviceConnection>> get connectionStates => _stateController.stream;
  Map<String, DeviceConnection> get connections => Map.unmodifiable(_connections);
  bool get isRunning => _isRunning;

  /// Notification sync service reference for routing notification messages
  NotificationSyncService? notificationSyncService;

  /// Start the persistent connection server
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _persistentPort);
      _server!.listen(_handleIncomingConnection);
    } catch (e) {
      _log.debug('Server bind failed on port $_persistentPort: $e');
    }

    // Start heartbeat checker
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeats());
  }

  /// Stop all connections
  Future<void> stop() async {
    _isRunning = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    for (final conn in _connections.values) {
      conn.socket?.destroy();
      conn.state = ConnectionState.disconnected;
    }
    _connections.clear();
    _emit();

    await _server?.close();
    _server = null;
  }

  /// Connect to a trusted device (persistent link)
  Future<bool> connectToDevice(DeviceModel device) async {
    if (device.ipAddress == null) return false;

    final existing = _connections[device.id];
    if (existing?.state == ConnectionState.connected) return true;

    _connections[device.id] = DeviceConnection(
      device: device,
      state: ConnectionState.connecting,
    );
    _emit();

    try {
      final socket = await Socket.connect(
        device.ipAddress!,
        _persistentPort,
        timeout: const Duration(seconds: 10),
      );

      // Send identity
      final identity = jsonEncode({
        'type': 'identity',
        'deviceId': device.id, // This will be replaced with our own ID in real use
        'deviceName': 'Sendate',
      });
      socket.add(utf8.encode('$identity\n'));
      await socket.flush();

      _connections[device.id] = DeviceConnection(
        device: device,
        state: ConnectionState.connected,
        socket: socket,
        connectedSince: DateTime.now(),
      );
      _emit();

      // Register with clipboard service
      clipboardService?.addConnectedDevice(device, socket);

      // Register with notification sync service
      notificationSyncService?.addConnectedSocket(socket);

      // Listen for incoming data on this connection
      _listenOnSocket(device.id, socket);

      return true;
    } catch (e) {
      _log.debug('Device connection failed (${device.name}): $e');
      _connections[device.id] = DeviceConnection(
        device: device,
        state: ConnectionState.disconnected,
      );
      _emit();
      return false;
    }
  }

  /// Disconnect from a device
  void disconnectDevice(String deviceId) {
    final conn = _connections[deviceId];
    if (conn != null) {
      if (conn.socket != null) {
        notificationSyncService?.removeConnectedSocket(conn.socket!);
      }
      conn.socket?.destroy();
      conn.state = ConnectionState.disconnected;
      clipboardService?.removeConnectedDevice(deviceId);
    }
    _connections.remove(deviceId);
    _emit();
  }

  /// Check if a device is connected
  bool isConnected(String deviceId) {
    return _connections[deviceId]?.state == ConnectionState.connected;
  }

  void _handleIncomingConnection(Socket socket) {
    // Read identity line
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        final str = buffer.toString();

        if (str.contains('\n')) {
          final lines = str.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            _processMessage(line, socket);
          }
          buffer.clear();
        }
      },
      onDone: () {
        // Find and mark as disconnected
        final entry = _connections.entries
            .where((e) => e.value.socket == socket)
            .firstOrNull;
        if (entry != null) {
          entry.value.state = ConnectionState.disconnected;
          entry.value.socket = null;
          clipboardService?.removeConnectedDevice(entry.key);
          _emit();
          _scheduleReconnect(entry.key);
        }
      },
      onError: (e) {
        _log.debug('Incoming connection error: $e');
        socket.destroy();
      },
    );
  }

  void _listenOnSocket(String deviceId, Socket socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        final str = buffer.toString();
        if (str.contains('\n')) {
          final lines = str.split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            _processMessage(line, socket);
          }
          buffer.clear();
        }
      },
      onDone: () {
        _connections[deviceId]?.state = ConnectionState.disconnected;
        _connections[deviceId]?.socket = null;
        clipboardService?.removeConnectedDevice(deviceId);
        _emit();
        _scheduleReconnect(deviceId);
      },
      onError: (e) {
        _log.debug('Socket listen error for device $deviceId: $e');
      },
    );
  }

  void _processMessage(String line, Socket socket) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'heartbeat':
          // Respond with heartbeat ack
          socket.add(utf8.encode('{"type":"heartbeat_ack"}\n'));
        case 'heartbeat_ack':
          // Connection is alive
          break;
        case 'clipboard':
          final content = json['content'] as String? ?? '';
          final senderId = json['deviceId'] as String? ?? '';
          final senderName = json['deviceName'] as String? ?? '';
          clipboardService?.onClipboardReceived(content, senderId, senderName);
        case 'identity':
          // Register this incoming connection
          final deviceId = json['deviceId'] as String? ?? '';
          final deviceName = json['deviceName'] as String? ?? '';
          if (deviceId.isNotEmpty) {
            final device = DeviceModel(
              id: deviceId,
              name: deviceName,
              deviceType: DeviceType.unknown,
              fingerprint: '',
              ipAddress: socket.remoteAddress.address,
            );
            _connections[deviceId] = DeviceConnection(
              device: device,
              state: ConnectionState.connected,
              socket: socket,
              connectedSince: DateTime.now(),
            );
            clipboardService?.addConnectedDevice(device, socket);
            notificationSyncService?.addConnectedSocket(socket);
            _emit();
          }
        case 'notification':
          // Forward notification from remote device to notification sync service
          notificationSyncService?.onRemoteNotificationReceived(json);
        case 'notification_removed':
          final notifId = json['id'] as String? ?? '';
          if (notifId.isNotEmpty) {
            notificationSyncService?.onRemoteNotificationRemoved(notifId);
          }
      }
    } catch (e) {
      _log.debug('Message processing failed: $e');
    }
  }

  void _sendHeartbeats() {
    for (final entry in _connections.entries.toList()) {
      if (entry.value.state == ConnectionState.connected && entry.value.socket != null) {
        try {
          entry.value.socket!.add(utf8.encode('{"type":"heartbeat"}\n'));
        } catch (e) {
          _log.debug('Heartbeat send failed for ${entry.key}: $e');
          entry.value.state = ConnectionState.disconnected;
          entry.value.socket = null;
          clipboardService?.removeConnectedDevice(entry.key);
          _emit();
          _scheduleReconnect(entry.key);
        }
      }
    }
  }

  void _scheduleReconnect(String deviceId) {
    final conn = _connections[deviceId];
    if (conn == null || !_isRunning) return;
    if (conn.reconnectAttempts >= _maxReconnectAttempts) return;

    conn.state = ConnectionState.reconnecting;
    conn.reconnectAttempts++;
    _emit();

    final delay = Duration(seconds: 2 * conn.reconnectAttempts);
    Future.delayed(delay, () {
      if (!_isRunning) return;
      if (_connections[deviceId]?.state != ConnectionState.reconnecting) return;
      connectToDevice(conn.device);
    });
  }

  void _emit() {
    _stateController.add(Map.unmodifiable(_connections));
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}
