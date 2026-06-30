import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../services/bluetooth/bluetooth_transfer_service.dart';
import '../../services/notification/notification_service.dart';
import '../../services/transfer/transfer_service.dart';
import '../models/device_model.dart';
import '../models/sendate_file.dart';
import '../models/transfer_model.dart';
import 'settings_provider.dart';
import 'transfer_provider.dart';
import '../../core/utils/global_navigator.dart';
import '../../services/conversion/conversion_service.dart';

// ---------------------------------------------------------------------------
// Conversion service provider
// ---------------------------------------------------------------------------
final conversionServiceProvider = Provider<ConversionService>((ref) {
  return ConversionService();
});

// ---------------------------------------------------------------------------
// Transfer service singleton
// ---------------------------------------------------------------------------
final transferServiceProvider = Provider<TransferService>((ref) {
  final service = TransferService();

  // Sync auto-convert setting
  service.autoConvertEnabled = ref.read(autoConvertProvider);

  // Set local device identity from Hive for the transfer protocol header
  try {
    final settingsBox = Hive.box(AppConstants.settingsBox);
    service.localDeviceId =
        settingsBox.get('device_id', defaultValue: '') as String;
    service.localDeviceName =
        settingsBox.get('device_name', defaultValue: '') as String;
  } catch (e) {
    debugPrint('[TransferServiceProvider] Failed to load device identity: $e');
  }

  // Wire receive-side notification — fires when a file is fully saved.
  service.onFileReceived = (transfer, savedPath) async {
    String finalPath = savedPath;
    String finalFileName = transfer.fileName;

    if (Platform.isAndroid && savedPath.toLowerCase().endsWith('.mov')) {
      final autoConvert = ref.read(autoConvertProvider);
      bool shouldConvert = autoConvert;

      if (!shouldConvert) {
        shouldConvert = await showConversionPrompt(transfer.fileName);
      }

      if (shouldConvert) {
        try {
          final conversionService = ConversionService();
          final newPath = await conversionService.convertFile(
            inputPath: savedPath,
            targetMimeType: 'video/mp4',
            targetExtension: 'mp4',
          );

          if (newPath != savedPath) {
            finalPath = newPath;
            finalFileName = finalPath.split('/').last;

            // Delete original .mov file
            final originalFile = File(savedPath);
            if (await originalFile.exists()) {
              await originalFile.delete();
            }

            // Update history
            ref.read(transferHistoryProvider.notifier).updateRecord(
              transfer.id,
              (t) => t.copyWith(
                filePath: finalPath,
                fileName: finalFileName,
                mimeType: 'video/mp4',
              ),
            );
          }
        } catch (e) {
          debugPrint('[TransferServiceProvider] Conversion failed: $e');
        }
      }
    }

    NotificationService.showFileReceived(
      fileName: finalFileName,
      filePath: finalPath,
      senderName: transfer.deviceName,
      fileSize: transfer.bytesTransferred,
    );
  };

  // Drive activeTransfersProvider and history from the WiFi/TCP transfer stream.
  _wireTransferStream(ref, service.transferStream);

  ref.onDispose(() => service.dispose());
  return service;
});

// ---------------------------------------------------------------------------
// BUG-08 FIX: Bluetooth transfer service — wired into the same pipeline so
// BT transfers appear in the active list, history, and notifications.
// ---------------------------------------------------------------------------
final bluetoothTransferServiceProvider =
    Provider<BluetoothTransferService>((ref) {
  final service = BluetoothTransferService();

  // Wire BT stream into the same active/history providers.
  _wireTransferStream(ref, service.transferStream, isBluetooth: true);

  ref.onDispose(() => service.dispose());
  return service;
});

/// Subscribe [stream] to the active-transfers and history providers.
/// Extracted so both WiFi and BT services share identical wiring logic.
void _wireTransferStream(
  Ref ref,
  Stream<TransferModel> stream, {
  bool isBluetooth = false,
}) {
  stream.listen((transfer) {
    if (transfer.state == TransferState.completed ||
        transfer.state == TransferState.failed ||
        transfer.state == TransferState.cancelled) {
      ref.read(transferHistoryProvider.notifier).addRecord(transfer);
      ref.read(activeTransfersProvider.notifier).removeTransfer(transfer.id);
      NotificationService.cancelTransferProgress(transfer.id);

      // Show a completion notification for BT transfers too
      if (isBluetooth && transfer.state == TransferState.completed &&
          transfer.direction == TransferDirection.received) {
        NotificationService.showFileReceived(
          fileName: transfer.fileName,
          filePath: transfer.filePath,
          senderName: transfer.deviceName,
          fileSize: transfer.bytesTransferred,
        );
      }
    } else {
      // Upsert active transfer
      final active = ref.read(activeTransfersProvider);
      if (active.any((t) => t.id == transfer.id)) {
        ref
            .read(activeTransfersProvider.notifier)
            .updateTransfer(transfer.id, (_) => transfer);
      } else {
        ref.read(activeTransfersProvider.notifier).addTransfer(transfer);
      }

      // Progress notification for WiFi sends
      if (!isBluetooth &&
          transfer.direction == TransferDirection.sent &&
          transfer.state == TransferState.sending) {
        NotificationService.showTransferSending(
          transferId: transfer.id,
          fileName: transfer.fileName,
          deviceName: transfer.deviceName,
          progressPercent: (transfer.progress * 100).round(),
          bytesTransferred: transfer.bytesTransferred,
          totalBytes: transfer.fileSize,
          speedBps: transfer.speed ?? 0,
        );
      }
    }
  });
}

// ---------------------------------------------------------------------------
// Transfer controller
// ---------------------------------------------------------------------------
final transferControllerProvider = Provider<TransferController>((ref) {
  return TransferController(ref);
});

class TransferController {
  final Ref _ref;

  TransferController(this._ref);

  TransferService get _service => _ref.read(transferServiceProvider);

  /// Start the transfer server to receive files.
  Future<void> startServer() async {
    if (!_service.isListening) {
      await _service.startServer();
    }
  }

  /// Send a single file.
  Future<TransferModel> sendFile({
    required SendateFile file,
    required DeviceModel target,
  }) async {
    return _service.sendFile(file: file, target: target);
  }

  // BUG-01 FIX: send multiple files in parallel (up to maxParallelTransfers)
  // instead of strictly sequential.  A failed/rejected file no longer blocks
  // the rest of the batch from starting.
  //
  // BUG-10 FIX: autoConvert is synced before each batch, and the batch-
  // complete notification is always fired.
  Future<void> sendFiles({
    required List<SendateFile> files,
    required DeviceModel target,
    TransferPriority priority = TransferPriority.normal,
  }) async {
    _service.autoConvertEnabled = _ref.read(autoConvertProvider);

    final sentFiles = <String>[];
    final failedFiles = <String>[];
    
    // Generate a single batch ID for this group of files
    final batchId = const Uuid().v4();
    final batchFileCount = files.length;

    // Split into batches of maxParallelTransfers and process concurrently.
    final batchSize = AppConstants.maxParallelTransfers;
    for (var i = 0; i < files.length; i += batchSize) {
      final batch = files.sublist(
          i,
          (i + batchSize) > files.length
              ? files.length
              : i + batchSize);

      final results = await Future.wait(
        batch.map((file) async {
          try {
            final result =
                await _service.sendFile(file: file, target: target, batchId: batchId, batchFileCount: batchFileCount);
            return result;
          } catch (e) {
            // Return a synthetic failed model so the caller can count it.
            return TransferModel(
              id: '',
              fileName: file.name,
              filePath: file.path,
              fileSize: file.size,
              mimeType: '',
              deviceId: target.id,
              deviceName: target.name,
              direction: TransferDirection.sent,
              state: TransferState.failed,
              startedAt: DateTime.now(),
              errorMessage: e.toString(),
            );
          }
        }),
      );

      for (final r in results) {
        if (r.state == TransferState.completed) {
          sentFiles.add(r.fileName);
        } else {
          failedFiles.add(r.fileName);
        }
      }
    }

    await NotificationService.showSendBatchComplete(
      deviceName: target.name,
      sentFiles: sentFiles,
      failedFiles: failedFiles,
    );
  }

  // BUG-10 FIX: sync autoConvert before scheduling; batch notification is
  // sent via the queue's onBatchComplete callback (wired in service layer).
  void scheduleFiles({
    required List<SendateFile> files,
    required DeviceModel target,
    required DateTime scheduledAt,
    TransferPriority priority = TransferPriority.normal,
  }) {
    // Sync the convert flag now so it's already set when the timer fires.
    _service.autoConvertEnabled = _ref.read(autoConvertProvider);
    _service.scheduleTransfer(
      files: files,
      target: target,
      scheduledAt: scheduledAt,
      priority: priority,
    );
  }

  /// Set bandwidth cap (bytes/sec). 0 = unlimited.
  void setBandwidthLimit(int bytesPerSec) {
    _service.bandwidthLimitBytesPerSec = bytesPerSec;
  }

  /// Pause an active transfer.
  void pause(String transferId) => _service.pauseTransfer(transferId);

  /// Resume a paused transfer.
  void resume(String transferId) => _service.resumeTransfer(transferId);

  /// Cancel a transfer.
  void cancel(String transferId) => _service.cancelTransfer(transferId);
}
