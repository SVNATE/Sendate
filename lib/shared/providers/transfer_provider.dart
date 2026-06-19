import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../models/transfer_model.dart';

/// Active transfers (in-progress, in-memory only)
final activeTransfersProvider =
    StateNotifierProvider<ActiveTransfersNotifier, List<TransferModel>>(
  (ref) => ActiveTransfersNotifier(),
);

class ActiveTransfersNotifier extends StateNotifier<List<TransferModel>> {
  ActiveTransfersNotifier() : super([]);

  void addTransfer(TransferModel transfer) {
    state = [...state, transfer];
  }

  void updateTransfer(String id, TransferModel Function(TransferModel) update) {
    state = state.map((t) => t.id == id ? update(t) : t).toList();
  }

  void removeTransfer(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void clear() {
    state = [];
  }
}

/// Transfer history — persisted to Hive
final transferHistoryProvider =
    StateNotifierProvider<TransferHistoryNotifier, List<TransferModel>>(
  (ref) => TransferHistoryNotifier(),
);

class TransferHistoryNotifier extends StateNotifier<List<TransferModel>> {
  TransferHistoryNotifier() : super([]) {
    _loadFromHive();
  }

  Box get _box => Hive.box(AppConstants.historyBox);

  void _loadFromHive() {
    try {
      final records = _box.values.toList();
      state = records.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return TransferModel(
          id: map['id'] as String,
          fileName: map['fileName'] as String,
          filePath: map['filePath'] as String? ?? '',
          fileSize: map['fileSize'] as int? ?? 0,
          mimeType: map['mimeType'] as String? ?? '',
          deviceId: map['deviceId'] as String? ?? '',
          deviceName: map['deviceName'] as String? ?? 'Unknown',
          direction: map['direction'] == 'sent'
              ? TransferDirection.sent
              : TransferDirection.received,
          state: _parseState(map['state'] as String?),
          progress: (map['progress'] as num?)?.toDouble() ?? 1.0,
          bytesTransferred: map['bytesTransferred'] as int? ?? 0,
          speed: map['speed'] as int?,
          startedAt: DateTime.tryParse(map['startedAt'] as String? ?? '') ??
              DateTime.now(),
          completedAt: map['completedAt'] != null
              ? DateTime.tryParse(map['completedAt'] as String)
              : null,
          duration: map['duration'] as int?,
        );
      }).toList();
    } catch (_) {
      state = [];
    }
  }

  void addRecord(TransferModel transfer) {
    state = [transfer, ...state];
    _saveToHive(transfer);
  }

  void removeRecord(String id) {
    state = state.where((t) => t.id != id).toList();
    _box.delete(id);
  }

  void clear() {
    state = [];
    _box.clear();
  }

  void _saveToHive(TransferModel t) {
    _box.put(t.id, {
      'id': t.id,
      'fileName': t.fileName,
      'filePath': t.filePath,
      'fileSize': t.fileSize,
      'mimeType': t.mimeType,
      'deviceId': t.deviceId,
      'deviceName': t.deviceName,
      'direction': t.direction == TransferDirection.sent ? 'sent' : 'received',
      'state': t.state.name,
      'progress': t.progress,
      'bytesTransferred': t.bytesTransferred,
      'speed': t.speed,
      'startedAt': t.startedAt.toIso8601String(),
      'completedAt': t.completedAt?.toIso8601String(),
      'duration': t.duration,
    });
  }

  TransferState _parseState(String? s) => switch (s) {
        'completed' => TransferState.completed,
        'failed' => TransferState.failed,
        'cancelled' => TransferState.cancelled,
        _ => TransferState.completed,
      };
}
