import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../services/clipboard/clipboard_sync_service.dart';

/// Clipboard sync service singleton
final clipboardSyncServiceProvider = Provider<ClipboardSyncService>((ref) {
  final service = ClipboardSyncService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Whether auto clipboard sync is enabled
final clipboardAutoSyncProvider = StateNotifierProvider<ClipboardAutoSyncNotifier, bool>(
  (ref) => ClipboardAutoSyncNotifier(ref),
);

class ClipboardAutoSyncNotifier extends StateNotifier<bool> {
  final Ref _ref;

  ClipboardAutoSyncNotifier(this._ref) : super(_load());

  static bool _load() {
    return Hive.box(AppConstants.settingsBox).get('clipboard_auto_sync', defaultValue: false) as bool;
  }

  Future<void> toggle() async {
    state = !state;
    await Hive.box(AppConstants.settingsBox).put('clipboard_auto_sync', state);

    final service = _ref.read(clipboardSyncServiceProvider);
    if (state) {
      service.startAutoSync();
    } else {
      service.stopAutoSync();
    }
  }
}

/// Stream of received clipboard messages
final clipboardReceivedProvider = StreamProvider<ClipboardMessage>((ref) {
  final service = ref.watch(clipboardSyncServiceProvider);
  return service.receivedClipboard;
});
