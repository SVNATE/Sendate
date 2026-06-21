import 'package:flutter/foundation.dart';
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
      final loaded = <TransferModel>[];
      for (final item in records) {
        try {
          final map = Map<String, dynamic>.from(item as Map);

          // BUG-12 FIX: tolerate both schemas:
          //   • WiFi/BT transfer schema  : 'direction' = 'sent'|'received', 'state' key
          //   • Old browser schema       : 'direction' = 'receive', 'status' key (legacy)
          // Normalise direction: accept 'sent', 'received', 'receive' → enum
          final rawDir = map['direction'] as String? ?? 'received';
          final direction = rawDir == 'sent'
              ? TransferDirection.sent
              : TransferDirection.received;

          // Normalise state: accept 'state' or legacy 'status' key
          final rawState =
              (map['state'] ?? map['status']) as String?;

          loaded.add(TransferModel(
            id: (map['id'] as String?) ?? '',
            fileName: (map['fileName'] as String?) ?? 'unknown',
            filePath: (map['filePath'] as String?) ?? '',
            fileSize: (map['fileSize'] as int?) ?? 0,
            mimeType: (map['mimeType'] as String?) ?? '',
            deviceId: (map['deviceId'] as String?) ?? '',
            deviceName: (map['deviceName'] as String?) ?? 'Unknown',
            direction: direction,
            state: _parseState(rawState),
            progress: (map['progress'] as num?)?.toDouble() ?? 1.0,
            bytesTransferred: (map['bytesTransferred'] as int?) ?? 0,
            speed: map['speed'] as int?,
            startedAt:
                DateTime.tryParse(map['startedAt'] as String? ??
                        map['timestamp'] as String? ??
                        '') ??
                    DateTime.now(),
            completedAt: map['completedAt'] != null
                ? DateTime.tryParse(map['completedAt'] as String)
                : null,
            duration: map['duration'] as int?,
          ));
        } catch (e) {
          // Skip individual corrupt records; don't wipe the whole list.
          debugPrint('[TransferProvider] Skipped corrupt history record: $e');
        }
      }
      state = loaded;
    } catch (e) {
      debugPrint('[TransferProvider] Failed to load transfer history: $e');
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
