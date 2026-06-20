import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/folder_sync/folder_sync_service.dart';
import 'transfer_service_provider.dart';

/// Provider for the FolderSyncService singleton.
final folderSyncServiceProvider = Provider<FolderSyncService>((ref) {
  final service = FolderSyncService();
  // Wire the transfer service so sync can actually send files.
  service.transferService = ref.read(transferServiceProvider);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the list of sync configurations. Async because it reads from Hive.
final folderSyncConfigsProvider =
    AsyncNotifierProvider<FolderSyncConfigsNotifier, List<FolderSyncConfig>>(
  FolderSyncConfigsNotifier.new,
);

class FolderSyncConfigsNotifier
    extends AsyncNotifier<List<FolderSyncConfig>> {
  FolderSyncService get _service => ref.read(folderSyncServiceProvider);

  @override
  Future<List<FolderSyncConfig>> build() => _service.getConfigs();

  Future<void> addConfig(FolderSyncConfig config) async {
    await _service.addConfig(config);
    state = AsyncData(await _service.getConfigs());
  }

  Future<void> removeConfig(String id) async {
    await _service.removeConfig(id);
    state = AsyncData(await _service.getConfigs());
  }

  Future<SyncResult> syncNow(FolderSyncConfig config) async {
    return _service.syncFolder(config);
  }
}
