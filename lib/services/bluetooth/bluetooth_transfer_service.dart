import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/logger.dart';
import '../../shared/models/transfer_model.dart';

/// Bluetooth RFCOMM file transfer service.
/// Transfers files over Bluetooth Classic when WiFi is unavailable.
class BluetoothTransferService {
  static const _channel = MethodChannel('com.svnate.sendate/bt_transfer');
  final _log = const AppLogger('BluetoothTransfer');
  final _transferController = StreamController<TransferModel>.broadcast();
  static const int _btChunkSize = 16384; // 16KB chunks for BT (slower than WiFi)

  Stream<TransferModel> get transferStream => _transferController.stream;

  /// Send a file over Bluetooth to a paired device
  Future<TransferModel> sendFile({
    required String filePath,
    required String deviceAddress,
    required String deviceName,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', filePath);
    }

    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();
    final transferId = const Uuid().v4();

    var transfer = TransferModel(
      id: transferId,
      fileName: fileName,
      filePath: filePath,
      fileSize: fileSize,
      mimeType: 'application/octet-stream',
      deviceId: 'bt-$deviceAddress',
      deviceName: deviceName,
      direction: TransferDirection.sent,
      state: TransferState.connecting,
      startedAt: DateTime.now(),
    );
    _transferController.add(transfer);

    try {
      // Connect via platform channel
      final connected = await _channel.invokeMethod<bool>('connect', {
        'address': deviceAddress,
      });

      if (connected != true) {
        transfer = transfer.copyWith(state: TransferState.failed, errorMessage: 'Connection failed');
        _transferController.add(transfer);
        return transfer;
      }

      // Send header
      final header = jsonEncode({
        'fileName': fileName,
        'fileSize': fileSize,
        'transferId': transferId,
      });
      await _channel.invokeMethod('send', {'data': utf8.encode(header)});

      // Send file in chunks
      transfer = transfer.copyWith(state: TransferState.sending);
      _transferController.add(transfer);

      final bytes = await file.readAsBytes();
      int bytesSent = 0;
      final stopwatch = Stopwatch()..start();

      for (var offset = 0; offset < bytes.length; offset += _btChunkSize) {
        final end = (offset + _btChunkSize).clamp(0, bytes.length);
        final chunk = bytes.sublist(offset, end);

        await _channel.invokeMethod('send', {'data': chunk});
        bytesSent += chunk.length;

        final elapsed = stopwatch.elapsedMilliseconds;
        final speed = elapsed > 0 ? (bytesSent * 1000) ~/ elapsed : 0;

        transfer = transfer.copyWith(
          progress: bytesSent / fileSize,
          bytesTransferred: bytesSent,
          speed: speed,
        );
        _transferController.add(transfer);
      }

      stopwatch.stop();
      await _channel.invokeMethod('disconnect');

      transfer = transfer.copyWith(
        state: TransferState.completed,
        progress: 1.0,
        bytesTransferred: fileSize,
        completedAt: DateTime.now(),
        duration: stopwatch.elapsedMilliseconds,
      );
      _transferController.add(transfer);
      return transfer;
    } catch (e) {
      transfer = transfer.copyWith(state: TransferState.failed, errorMessage: e.toString());
      _transferController.add(transfer);
      return transfer;
    }
  }

  /// Start listening for incoming BT transfers
  Future<void> startServer() async {
    try {
      _channel.setMethodCallHandler(_handleIncoming);
      await _channel.invokeMethod('startServer');
    } catch (e) {
      _log.debug('startServer failed: $e');
    }
  }

  Future<dynamic> _handleIncoming(MethodCall call) async {
    if (call.method == 'onFileReceived') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final transfer = TransferModel(
        id: args['transferId'] as String? ?? const Uuid().v4(),
        fileName: args['fileName'] as String? ?? 'bluetooth_file',
        filePath: args['savedPath'] as String? ?? '',
        fileSize: args['fileSize'] as int? ?? 0,
        mimeType: 'application/octet-stream',
        deviceId: 'bt-${args['address'] ?? ''}',
        deviceName: args['deviceName'] as String? ?? 'Bluetooth',
        direction: TransferDirection.received,
        state: TransferState.completed,
        progress: 1.0,
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
      );
      _transferController.add(transfer);
    }
  }

  Future<void> dispose() async {
    await _transferController.close();
  }
}
