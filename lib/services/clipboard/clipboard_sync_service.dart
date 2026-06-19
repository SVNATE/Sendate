import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/models/device_model.dart';
import 'native_clipboard_listener.dart';

/// Direct clipboard sync protocol.
/// Uses NATIVE clipboard listener for real-time detection across all apps.
/// Sends clipboard content directly (not as .txt file).
/// Receiver writes to system clipboard immediately.
class ClipboardSyncService {
  final _receivedController = StreamController<ClipboardMessage>.broadcast();
  final NativeClipboardListener _nativeListener = NativeClipboardListener();
  StreamSubscription? _nativeSubscription;

  String? _lastClipboardContent;
  bool _autoSyncEnabled = false;
  bool _isListening = false;
  final List<_ConnectedDevice> _connectedDevices = [];

  /// Known devices that can receive clipboard via direct TCP fallback.
  /// Updated when devices are discovered on the network.
  final List<DeviceModel> _knownDevices = [];

  Stream<ClipboardMessage> get receivedClipboard => _receivedController.stream;
  bool get isAutoSyncEnabled => _autoSyncEnabled;

  /// Start clipboard monitoring using NATIVE listener (works from any app, not just Flutter)
  void startAutoSync() {
    _autoSyncEnabled = true;
    _nativeListener.start();
    _nativeSubscription?.cancel();
    _nativeSubscription = _nativeListener.clipboardChanges.listen((text) {
      if (!_autoSyncEnabled) return;
      if (text == _lastClipboardContent) return;

      // Check if we have ANY target devices (persistent connection OR known via discovery)
      if (_connectedDevices.isEmpty && _knownDevices.isEmpty) {
        debugPrint('[ClipboardSync] No connected or known devices to broadcast to');
        return;
      }

      _lastClipboardContent = text;
      broadcastClipboard(text);
    });
    debugPrint('[ClipboardSync] Auto-sync started. Connected: ${_connectedDevices.length}, Known: ${_knownDevices.length}');
  }

  /// Stop clipboard monitoring
  void stopAutoSync() {
    _autoSyncEnabled = false;
    _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _nativeListener.stop();
    debugPrint('[ClipboardSync] Auto-sync stopped');
  }

  /// Register a connected device for clipboard sync (via persistent connection)
  void addConnectedDevice(DeviceModel device, Socket socket) {
    _connectedDevices.removeWhere((d) => d.device.id == device.id);
    _connectedDevices.add(_ConnectedDevice(device: device, socket: socket));
    debugPrint('[ClipboardSync] Device connected: ${device.name} (${device.ipAddress})');
  }

  /// Remove a connected device
  void removeConnectedDevice(String deviceId) {
    _connectedDevices.removeWhere((d) => d.device.id == deviceId);
    debugPrint('[ClipboardSync] Device disconnected: $deviceId');
  }

  /// Update the list of known (discovered) devices that can receive clipboard via TCP fallback.
  /// Called when device discovery finds/updates devices on the network.
  void updateKnownDevices(List<DeviceModel> devices) {
    _knownDevices.clear();
    _knownDevices.addAll(devices.where((d) => d.ipAddress != null));
    debugPrint('[ClipboardSync] Known devices updated: ${_knownDevices.length} reachable');
  }

  /// Send current clipboard to ALL known/connected devices (used by notification button).
  /// Returns the text that was sent, or null if clipboard was empty.
  Future<String?> sendClipboardToAll() async {
    final text = await _nativeListener.getClipboard();
    if (text.isEmpty) return null;
    await broadcastClipboard(text);
    return text;
  }

  /// Called from background isolate when native clipboard change is detected.
  /// Triggers broadcast to all connected devices.
  void onLocalClipboardChanged(String text) {
    if (!_autoSyncEnabled) return;
    if (text == _lastClipboardContent) return;
    if (_connectedDevices.isEmpty && _knownDevices.isEmpty) return;
    _lastClipboardContent = text;
    broadcastClipboard(text);
  }

  /// Send clipboard content to a specific device (manual send)
  Future<bool> sendClipboardTo(DeviceModel device, {String? content}) async {
    final text = content ?? await _nativeListener.getClipboard();
    if (text.isEmpty) return false;

    final targetSocket = _connectedDevices
        .where((d) => d.device.id == device.id)
        .firstOrNull
        ?.socket;

    if (targetSocket != null) {
      return _sendViaSocket(targetSocket, text);
    }

    // Fallback: direct TCP connection
    if (device.ipAddress != null) {
      return _sendViaTcp(device.ipAddress!, device.port ?? AppConstants.transferPort, text);
    }

    return false;
  }

  /// Send clipboard to ALL connected/known devices.
  /// Uses persistent socket first, falls back to direct TCP for known devices.
  Future<void> broadcastClipboard(String text) async {
    final sentDeviceIds = <String>{};

    // 1. Send via persistent connections (fastest, already-open sockets)
    for (final connected in _connectedDevices) {
      final success = await _sendViaSocket(connected.socket, text);
      if (success) {
        sentDeviceIds.add(connected.device.id);
      } else {
        debugPrint('[ClipboardSync] Socket send failed to ${connected.device.name}, will retry via TCP');
      }
    }

    // 2. Fallback: send via direct TCP to known devices that weren't reached via socket
    for (final device in _knownDevices) {
      if (sentDeviceIds.contains(device.id)) continue; // Already sent
      if (device.ipAddress == null) continue;

      final success = await _sendViaTcp(
        device.ipAddress!,
        device.port ?? AppConstants.transferPort,
        text,
      );
      if (success) {
        sentDeviceIds.add(device.id);
      } else {
        debugPrint('[ClipboardSync] TCP fallback failed to ${device.name} (${device.ipAddress})');
      }
    }

    if (sentDeviceIds.isEmpty) {
      debugPrint('[ClipboardSync] WARNING: Clipboard change detected but failed to send to any device');
    } else {
      debugPrint('[ClipboardSync] Broadcast sent to ${sentDeviceIds.length} device(s)');
    }
  }

  /// Handle incoming clipboard message
  Future<void> onClipboardReceived(String content, String senderId, String senderName) async {
    // Write to system clipboard via native channel (works without Flutter focus)
    _nativeListener.markAsRemote(content);
    await _nativeListener.setClipboard(content);

    // Prevent echo
    _lastClipboardContent = content;

    // Emit to stream
    _receivedController.add(ClipboardMessage(
      content: content,
      senderId: senderId,
      senderName: senderName,
      timestamp: DateTime.now(),
    ));

    // Save to clipboard history
    _saveToHistory(content, senderName);
  }

  Future<bool> _sendViaSocket(Socket socket, String text) async {
    try {
      final message = jsonEncode({
        'type': 'clipboard',
        'content': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = utf8.encode(message);
      // Protocol: [4-byte length][message]
      final lenBytes = _intToBytes(bytes.length);
      socket.add(lenBytes);
      socket.add(bytes);
      await socket.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendViaTcp(String ip, int port, String text) async {
    try {
      // Use clipboard-specific port (transfer port + 2)
      final socket = await Socket.connect(ip, port + 2, timeout: const Duration(seconds: 5));
      final message = jsonEncode({
        'type': 'clipboard',
        'content': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      final bytes = utf8.encode(message);
      socket.add(_intToBytes(bytes.length));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start clipboard receive server
  Future<ServerSocket?> startServer(int port) async {
    if (_isListening) return null;
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, port + 2);
      _isListening = true;
      server.listen(_handleIncoming);
      return server;
    } catch (_) {
      return null;
    }
  }

  void _handleIncoming(Socket socket) async {
    try {
      final data = <int>[];
      await for (final chunk in socket) {
        data.addAll(chunk);
      }

      if (data.length < 4) { socket.destroy(); return; }

      final msgLen = _bytesToInt(data.sublist(0, 4));
      final msgBytes = data.sublist(4, 4 + msgLen);
      final json = jsonDecode(utf8.decode(msgBytes)) as Map<String, dynamic>;

      if (json['type'] == 'clipboard') {
        final content = json['content'] as String;
        final senderId = json['deviceId'] as String? ?? socket.remoteAddress.address;
        final senderName = json['deviceName'] as String? ?? 'Unknown';
        await onClipboardReceived(content, senderId, senderName);
      }

      socket.destroy();
    } catch (_) {
      socket.destroy();
    }
  }

  void _saveToHistory(String content, String senderName) {
    try {
      final box = Hive.box(AppConstants.historyBox);
      box.put('clip_${DateTime.now().millisecondsSinceEpoch}', {
        'id': 'clip_${DateTime.now().millisecondsSinceEpoch}',
        'type': 'clipboard',
        'content': content.length > 200 ? '${content.substring(0, 200)}...' : content,
        'deviceName': senderName,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  List<int> _intToBytes(int value) {
    final bytes = List<int>.filled(4, 0);
    bytes[0] = (value >> 24) & 0xFF;
    bytes[1] = (value >> 16) & 0xFF;
    bytes[2] = (value >> 8) & 0xFF;
    bytes[3] = value & 0xFF;
    return bytes;
  }

  int _bytesToInt(List<int> bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  void dispose() {
    stopAutoSync();
    _nativeListener.dispose();
    _receivedController.close();
  }
}

class ClipboardMessage {
  final String content;
  final String senderId;
  final String senderName;
  final DateTime timestamp;

  ClipboardMessage({
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
  });
}

class _ConnectedDevice {
  final DeviceModel device;
  final Socket socket;
  _ConnectedDevice({required this.device, required this.socket});
}
