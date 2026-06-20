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

      // Show completion / failure notification
      if (transfer.direction == TransferDirection.sent) {
        if (transfer.state == TransferState.completed) {
          NotificationService.showTransferComplete(
            fileName: transfer.fileName,
            deviceName: transfer.deviceName,
            isSend: true,
          );
        } else if (transfer.state == TransferState.failed) {
          NotificationService.showTransferFailed(
            fileName: transfer.fileName,
            error: transfer.errorMessage ?? 'Unknown error',
          );
        }
      }
      // Received-side completion is handled in main.dart's onFileReceived
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

  /// Enqueue multiple files for sequential sending
  void sendFiles({
    required List<String> filePaths,
    required DeviceModel target,
  }) {
    // Sync auto-convert setting before sending
    _service.autoConvertEnabled = _ref.read(autoConvertProvider);
    _service.enqueueFiles(filePaths: filePaths, target: target);
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
