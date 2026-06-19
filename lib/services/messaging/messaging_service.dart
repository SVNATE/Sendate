import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// Message model
class Message {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final String recipientId;
  final DateTime timestamp;
  final bool delivered;
  final bool read;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.timestamp,
    this.delivered = false,
    this.read = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'text': text, 'senderId': senderId,
    'senderName': senderName, 'recipientId': recipientId,
    'timestamp': timestamp.toIso8601String(),
    'delivered': delivered, 'read': read,
  };

  factory Message.fromMap(Map<String, dynamic> map) => Message(
    id: map['id'] as String,
    text: map['text'] as String,
    senderId: map['senderId'] as String,
    senderName: map['senderName'] as String? ?? '',
    recipientId: map['recipientId'] as String,
    timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
    delivered: map['delivered'] as bool? ?? false,
    read: map['read'] as bool? ?? false,
  );

  Message copyWith({bool? delivered, bool? read}) => Message(
    id: id, text: text, senderId: senderId, senderName: senderName,
    recipientId: recipientId, timestamp: timestamp,
    delivered: delivered ?? this.delivered, read: read ?? this.read,
  );
}

/// Offline messaging service.
/// Messages are queued in Hive and delivered when the target device is discovered.
class MessagingService {
  static const _messagesBox = 'messages';
  static const _pendingBox = 'pending_messages';
  final _log = const AppLogger('Messaging');
  final _messageController = StreamController<Message>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;

  /// Send a message to a device (queues if offline)
  Future<void> sendMessage({
    required String text,
    required String senderId,
    required String senderName,
    required String recipientId,
    String? recipientIp,
    int? recipientPort,
  }) async {
    final message = Message(
      id: const Uuid().v4(),
      text: text,
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      timestamp: DateTime.now(),
    );

    // Try to deliver immediately if we have connection info
    if (recipientIp != null) {
      final delivered = await _deliverMessage(message, recipientIp, recipientPort ?? AppConstants.transferPort);
      if (delivered) {
        await _saveMessage(message.copyWith(delivered: true));
        return;
      }
    }

    // Queue for later delivery
    await _saveMessage(message);
    await _queuePending(message);
  }

  /// Flush pending messages to a device that just came online
  Future<int> flushPendingMessages(String deviceId, String ip, int port) async {
    final box = await Hive.openBox(_pendingBox);
    final pending = box.values
        .map((v) => Message.fromMap(Map<String, dynamic>.from(v as Map)))
        .where((m) => m.recipientId == deviceId && !m.delivered)
        .toList();

    int delivered = 0;
    for (final message in pending) {
      final success = await _deliverMessage(message, ip, port);
      if (success) {
        await box.delete(message.id);
        await _updateMessageDelivered(message.id);
        delivered++;
      }
    }
    return delivered;
  }

  /// Get all messages for a conversation with a device
  Future<List<Message>> getMessages(String deviceId, String myId) async {
    final box = await Hive.openBox(_messagesBox);
    return box.values
        .map((v) => Message.fromMap(Map<String, dynamic>.from(v as Map)))
        .where((m) =>
            (m.senderId == myId && m.recipientId == deviceId) ||
            (m.senderId == deviceId && m.recipientId == myId))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Handle incoming message from network
  Future<void> receiveMessage(Message message) async {
    await _saveMessage(message.copyWith(delivered: true));
    _messageController.add(message);
  }

  /// Start message server (listens on a secondary port)
  Future<ServerSocket?> startMessageServer(int port) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, port + 1);
      server.listen(_handleIncoming);
      return server;
    } catch (e) {
      _log.debug('Message server bind failed on port ${port + 1}: $e');
      return null;
    }
  }

  void _handleIncoming(Socket socket) async {
    try {
      final data = <int>[];
      await for (final chunk in socket) {
        data.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(data));
      if (json['type'] == 'message') {
        final message = Message.fromMap(Map<String, dynamic>.from(json['data'] as Map));
        await receiveMessage(message);
        // Send ACK
        socket.add(utf8.encode(jsonEncode({'type': 'ack', 'id': message.id})));
        await socket.flush();
      }
      socket.destroy();
    } catch (e) {
      _log.debug('Incoming message handling failed: $e');
      socket.destroy();
    }
  }

  Future<bool> _deliverMessage(Message message, String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port + 1, timeout: const Duration(seconds: 5));
      final payload = jsonEncode({
        'type': 'message',
        'data': message.toMap(),
      });
      socket.add(utf8.encode(payload));
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      _log.debug('Message delivery failed to $ip:${port + 1}: $e');
      return false;
    }
  }

  Future<void> _saveMessage(Message message) async {
    final box = await Hive.openBox(_messagesBox);
    await box.put(message.id, message.toMap());
  }

  Future<void> _queuePending(Message message) async {
    final box = await Hive.openBox(_pendingBox);
    await box.put(message.id, message.toMap());
  }

  Future<void> _updateMessageDelivered(String id) async {
    final box = await Hive.openBox(_messagesBox);
    final data = box.get(id);
    if (data != null) {
      final map = Map<String, dynamic>.from(data as Map);
      map['delivered'] = true;
      await box.put(id, map);
    }
  }

  /// Delete all messages for a device
  Future<void> clearConversation(String deviceId, String myId) async {
    final box = await Hive.openBox(_messagesBox);
    final toDelete = box.keys.where((key) {
      final map = Map<String, dynamic>.from(box.get(key) as Map);
      return (map['senderId'] == myId && map['recipientId'] == deviceId) ||
          (map['senderId'] == deviceId && map['recipientId'] == myId);
    }).toList();
    for (final key in toDelete) {
      await box.delete(key);
    }
  }

  Future<void> dispose() async {
    await _messageController.close();
  }
}
