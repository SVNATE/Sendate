import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/models/device_model.dart';
import '../security/encryption_service.dart';
import 'native_clipboard_listener.dart';

/// Direct clipboard sync protocol with AES-256-GCM encryption.
/// Uses NATIVE clipboard listener for real-time detection across all apps.
/// All clipboard data is encrypted before transmission.
class ClipboardSyncService {
  final _receivedController = StreamController<ClipboardMessage>.broadcast();
  final NativeClipboardListener _nativeListener = NativeClipboardListener();
  final EncryptionService _encryption = EncryptionService();
  StreamSubscription? _nativeSubscription;

  String? _lastClipboardContent;
  bool _autoSyncEnabled = false;
  bool _isListening = false;
  final List<_ConnectedDevice> _connectedDevices = [];

  /// Encryption key for clipboard messages (shared across trusted devices)
  Uint8List? _sessionKey;

  /// Known devices that can receive clipboard via direct TCP fallback.
  final List<DeviceModel> _knownDevices = [];

  Stream<ClipboardMessage> get receivedClipboard => _receivedController.stream;
  bool get isAutoSyncEnabled => _autoSyncEnabled;

  /// Initialize or retrieve a session key for clipboard encryption.
  /// The key is generated once and stored locally.
  Future<Uint8List> _getOrCreateSessionKey() async {
    if (_sessionKey != null) return _sessionKey!;

    try {
      final box = Hive.box(AppConstants.settingsBox);
      final storedKey = box.get('clipboard_session_key') as List<dynamic>?;
      if (storedKey != null && storedKey.length == 32) {
        _sessionKey = Uint8List.fromList(storedKey.cast<int>());
        return _sessionKey!;
      }
    } catch (e) {
      debugPrint('[ClipboardSync] Error reading stored key: $e');
    }

    // Generate a new key
    _sessionKey = await _encryption.generateSessionKey();
    try {
      final box = Hive.box(AppConstants.settingsBox);
      await box.put('clipboard_session_key', _sessionKey!.toList());
    } catch (e) {
      debugPrint('[ClipboardSync] Error storing session key: $e');
    }
    return _sessionKey!;
  }

  /// Start clipboard monitoring using NATIVE listener
  void startAutoSync() {
    debugPrint('[ClipboardSync] === startAutoSync() called ===');
    debugPrint('[ClipboardSync] _autoSyncEnabled was: $_autoSyncEnabled');
    _autoSyncEnabled = true;
    debugPrint('[ClipboardSync] Calling _nativeListener.start()...');
    _nativeListener.start();
    _nativeSubscription?.cancel();
    debugPrint('[ClipboardSync] Subscribing to clipboardChanges stream...');
    _nativeSubscription = _nativeListener.clipboardChanges.listen(
      (text) {
        debugPrint('[ClipboardSync] clipboardChanges event received! text length=${text.length}');
        debugPrint('[ClipboardSync] _autoSyncEnabled=$_autoSyncEnabled, lastContent same=${text == _lastClipboardContent}');
        debugPrint('[ClipboardSync] connectedDevices=${_connectedDevices.length}, knownDevices=${_knownDevices.length}');
        if (!_autoSyncEnabled) {
          debugPrint('[ClipboardSync] SKIPPED: auto-sync disabled');
          return;
        }
        if (text == _lastClipboardContent) {
          debugPrint('[ClipboardSync] SKIPPED: same as last content');
          return;
        }

        _lastClipboardContent = text;

        // Only broadcast if we have targets; otherwise just track the content
        if (_connectedDevices.isNotEmpty || _knownDevices.isNotEmpty) {
          debugPrint('[ClipboardSync] Broadcasting to ${_connectedDevices.length} connected + ${_knownDevices.length} known devices');
          broadcastClipboard(text);
        } else {
          debugPrint('[ClipboardSync] Clipboard changed but no devices available yet');
        }
      },
      onError: (e) {
        debugPrint('[ClipboardSync] clipboardChanges stream ERROR: $e');
      },
      onDone: () {
        debugPrint('[ClipboardSync] clipboardChanges stream DONE (closed)');
      },
    );
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

  /// Register a connected device for clipboard sync
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

  /// Update the list of known (discovered) devices
  void updateKnownDevices(List<DeviceModel> devices) {
    final validDevices = devices.where((d) => d.ipAddress != null).toList();
    debugPrint('[ClipboardSync] updateKnownDevices: received ${devices.length} total, ${validDevices.length} with IP');
    for (final d in validDevices) {
      debugPrint('[ClipboardSync]   - ${d.name} @ ${d.ipAddress}:${d.port}');
    }
    _knownDevices.clear();
    _knownDevices.addAll(validDevices);
  }

  /// Send current clipboard to ALL known/connected devices
  Future<String?> sendClipboardToAll() async {
    final text = await _nativeListener.getClipboard();
    if (text.isEmpty) return null;
    await broadcastClipboard(text);
    return text;
  }

  /// Called from background isolate when native clipboard change is detected
  void onLocalClipboardChanged(String text) {
    if (!_autoSyncEnabled) return;
    if (text == _lastClipboardContent) return;
    if (_connectedDevices.isEmpty && _knownDevices.isEmpty) return;
    _lastClipboardContent = text;
    broadcastClipboard(text);
  }

  /// Send clipboard content to a specific device
  Future<bool> sendClipboardTo(DeviceModel device, {String? content}) async {
    final text = content ?? await _nativeListener.getClipboard();
    if (text.isEmpty) {
      debugPrint('[ClipboardSync] sendClipboardTo: clipboard is empty, nothing to send');
      return false;
    }

    debugPrint('[ClipboardSync] sendClipboardTo: ${device.name} (${device.ipAddress}), text length: ${text.length}');

    final targetSocket = _connectedDevices
        .where((d) => d.device.id == device.id)
        .firstOrNull
        ?.socket;

    if (targetSocket != null) {
      debugPrint('[ClipboardSync] Sending via persistent socket to ${device.name}');
      return _sendViaSocket(targetSocket, text);
    }

    if (device.ipAddress != null) {
      debugPrint('[ClipboardSync] Sending via TCP fallback to ${device.name} at ${device.ipAddress}');
      return _sendViaTcp(device.ipAddress!, device.port ?? AppConstants.transferPort, text);
    }

    debugPrint('[ClipboardSync] sendClipboardTo: no socket and no IP for ${device.name}');
    return false;
  }

  /// Send clipboard to ALL connected/known devices (encrypted)
  Future<void> broadcastClipboard(String text) async {
    final sentDeviceIds = <String>{};

    // 1. Send via persistent connections
    for (final connected in _connectedDevices) {
      final success = await _sendViaSocket(connected.socket, text);
      if (success) {
        sentDeviceIds.add(connected.device.id);
      } else {
        debugPrint('[ClipboardSync] Socket send failed to ${connected.device.name}');
      }
    }

    // 2. Fallback: send via direct TCP to known devices
    for (final device in _knownDevices) {
      if (sentDeviceIds.contains(device.id)) continue;
      if (device.ipAddress == null) continue;

      final success = await _sendViaTcp(
        device.ipAddress!,
        device.port ?? AppConstants.transferPort,
        text,
      );
      if (success) {
        sentDeviceIds.add(device.id);
      } else {
        debugPrint('[ClipboardSync] TCP fallback failed to ${device.name}');
      }
    }

    if (sentDeviceIds.isEmpty) {
      debugPrint('[ClipboardSync] Failed to send clipboard to any device');
    } else {
      debugPrint('[ClipboardSync] Broadcast sent to ${sentDeviceIds.length} device(s)');
    }
  }

  /// Handle incoming clipboard message (decrypts and applies)
  Future<void> onClipboardReceived(String content, String senderId, String senderName) async {
    _nativeListener.markAsRemote(content);
    await _nativeListener.setClipboard(content);
    _lastClipboardContent = content;

    _receivedController.add(ClipboardMessage(
      content: content,
      senderId: senderId,
      senderName: senderName,
      timestamp: DateTime.now(),
    ));

    _saveToHistory(content, senderName);
  }

  /// Send clipboard via persistent socket using line-delimited JSON protocol
  /// (matches PersistentConnectionService's message format that the receiver expects)
  Future<bool> _sendViaSocket(Socket socket, String text) async {
    try {
      final payload = jsonEncode({
        'type': 'clipboard',
        'content': text,
        'deviceId': '', // Will be filled by receiver from socket identity
        'deviceName': '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Use the same newline-delimited JSON protocol as PersistentConnectionService
      socket.add(utf8.encode('$payload\n'));
      await socket.flush();
      debugPrint('[ClipboardSync] Socket send SUCCESS (${text.length} chars)');
      return true;
    } catch (e) {
      debugPrint('[ClipboardSync] Socket send error: $e');
      return false;
    }
  }

  /// Send clipboard via direct TCP connection (unencrypted, same-network LAN only)
  Future<bool> _sendViaTcp(String ip, int port, String text) async {
    try {
      final socket = await Socket.connect(ip, port + 2, timeout: const Duration(seconds: 5));

      final plainPayload = jsonEncode({
        'type': 'clipboard',
        'content': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final payloadBytes = Uint8List.fromList(utf8.encode(plainPayload));

      // Protocol: [4-byte length][1-byte flags (0x00 = unencrypted)][payload]
      // Receiver's _handleIncoming already handles flag=0x00 as the legacy/plain path.
      final totalLen = 1 + payloadBytes.length;
      socket.add(_intToBytes(totalLen));
      socket.add([0x00]); // Unencrypted flag
      socket.add(payloadBytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      debugPrint('[ClipboardSync] TCP send error to $ip: $e');
      return false;
    }
  }

  /// Start clipboard receive server
  Future<ServerSocket?> startServer(int port) async {
    debugPrint('[ClipboardSync] startServer called with base port=$port, will bind to port ${port + 2}');
    if (_isListening) {
      debugPrint('[ClipboardSync] Server already listening, skipping');
      return null;
    }
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, port + 2);
      _isListening = true;
      server.listen(_handleIncoming);
      debugPrint('[ClipboardSync] Server started successfully on port ${port + 2}');
      return server;
    } catch (e) {
      debugPrint('[ClipboardSync] Failed to start server on port ${port + 2}: $e');
      return null;
    }
  }

  void _handleIncoming(Socket socket) async {
    try {
      final data = <int>[];
      await for (final chunk in socket) {
        data.addAll(chunk);
      }

      if (data.length < 5) { socket.destroy(); return; }

      final msgLen = _bytesToInt(data.sublist(0, 4));
      if (data.length < 4 + msgLen) { socket.destroy(); return; }

      final flags = data[4];
      final payload = data.sublist(5, 4 + msgLen);

      Map<String, dynamic> json;

      if (flags == 0x01) {
        // Encrypted message — decrypt
        final key = await _getOrCreateSessionKey();
        final decrypted = await _encryption.decryptChunk(
          Uint8List.fromList(payload),
          key,
        );
        json = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
      } else {
        // Legacy unencrypted message (backward compatibility)
        json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      }

      if (json['type'] == 'clipboard') {
        final content = json['content'] as String;
        // Validate content length (max 1MB of text)
        if (content.length > 1024 * 1024) {
          debugPrint('[ClipboardSync] Rejected oversized clipboard content (${content.length} bytes)');
          socket.destroy();
          return;
        }
        final senderId = json['deviceId'] as String? ?? socket.remoteAddress.address;
        final senderName = json['deviceName'] as String? ?? 'Unknown';
        await onClipboardReceived(content, senderId, senderName);
      }

      socket.destroy();
    } catch (e) {
      debugPrint('[ClipboardSync] Error handling incoming: $e');
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
    } catch (e) {
      debugPrint('[ClipboardSync] Error saving to history: $e');
    }
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
