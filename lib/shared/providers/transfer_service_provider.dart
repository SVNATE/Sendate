import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../services/notification/notification_service.dart';
import '../../services/transfer/transfer_service.dart';
import '../models/device_model.dart';
import '../models/transfer_model.dart';
import 'settings_provider.dart';
import 'transfer_provider.dart';

/// Transfer service singleton
final transferServiceProvider = Provider<TransferService>((ref) {
  final service = TransferService();

  // Sync auto-convert setting
  service.autoConvertEnabled = ref.read(autoConvertProvider);

  // Set local device identity from Hive for the transfer protocol header
  try {
    final settingsBox = Hive.box(AppConstants.settingsBox);
    service.localDeviceId = settingsBox.get('device_id', defaultValue: '') as String;
    service.localDeviceName = settingsBox.get('device_name', defaultValue: '') as String;
  } catch (e) {
    debugPrint('[TransferServiceProvider] Failed to load device identity: $e');
  }

  // Wire receive-side notification — fires as soon as a file is fully saved.
  service.onFileReceived = (transfer, savedPath) {
    NotificationService.showFileReceived(
      fileName: transfer.fileName,
      senderName: transfer.deviceName,
      fileSize: transfer.bytesTransferred,
    );
  };

  // Record completed/failed/cancelled transfers to history
  // and drive status-bar progress notifications
  service.transferStream.listen((transfer) {
    if (transfer.state == TransferState.completed ||
        transfer.state == TransferState.failed ||
        transfer.state == TransferState.cancelled) {
      ref.read(transferHistoryProvider.notifier).addRecord(transfer);
      ref.read(activeTransfersProvider.notifier).removeTransfer(transfer.id);

      // Dismiss the ongoing progress notification
      NotificationService.cancelTransferProgress(transfer.id);
      // Batch send summary is shown by TransferController.sendFiles() after all files finish.
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

      // Show / update status-bar progress notification while sending
      if (transfer.direction == TransferDirection.sent &&
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

  ref.onDispose(() => service.dispose());
  return service;
});

/// Controller for sending files and managing transfers
final transferControllerProvider = Provider<TransferController>((ref) {
  return TransferController(ref);
});

class TransferController {
  final Ref _ref;

  TransferController(this._ref);

  TransferService get _service => _ref.read(transferServiceProvider);

  /// Start the transfer server to receive files
  Future<void> startServer() async {
    if (!_service.isListening) {
      await _service.startServer();
    }
  }

  /// Send a single file
  Future<TransferModel> sendFile({
    required String filePath,
    required DeviceModel target,
  }) async {
    return _service.sendFile(filePath: filePath, target: target);
  }

  /// Send multiple files sequentially and show ONE summary notification when done.
  Future<void> sendFiles({
    required List<String> filePaths,
    required DeviceModel target,
    TransferPriority priority = TransferPriority.normal,
  }) async {
    _service.autoConvertEnabled = _ref.read(autoConvertProvider);
    final sentFiles = <String>[];
    final failedFiles = <String>[];
    for (final path in filePaths) {
      try {
        final result = await _service.sendFile(filePath: path, target: target);
        if (result.state == TransferState.completed) {
          sentFiles.add(result.fileName);
        } else {
          failedFiles.add(result.fileName);
        }
      } catch (e) {
        failedFiles.add(path.split('/').last);
      }
    }
    await NotificationService.showSendBatchComplete(
      deviceName: target.name,
      sentFiles: sentFiles,
      failedFiles: failedFiles,
    );
  }

  /// Schedule files to be sent at a specific time
  void scheduleFiles({
    required List<String> filePaths,
    required DeviceModel target,
    required DateTime scheduledAt,
    TransferPriority priority = TransferPriority.normal,
  }) {
    _service.autoConvertEnabled = _ref.read(autoConvertProvider);
    _service.scheduleTransfer(
        filePaths: filePaths,
        target: target,
        scheduledAt: scheduledAt,
        priority: priority);
  }

  /// Set bandwidth cap (bytes/sec). 0 = unlimited.
  void setBandwidthLimit(int bytesPerSec) {
    _service.bandwidthLimitBytesPerSec = bytesPerSec;
  }

  /// Pause an active transfer
  void pause(String transferId) {
    _service.pauseTransfer(transferId);
  }

  /// Resume a paused transfer
  void resume(String transferId) {
    _service.resumeTransfer(transferId);
  }

  /// Cancel a transfer
  void cancel(String transferId) {
    _service.cancelTransfer(transferId);
  }
}
