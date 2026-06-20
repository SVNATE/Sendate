import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../services/notification_sync/notification_sync_service.dart';

/// Singleton provider for NotificationSyncService.
final notificationSyncServiceProvider = Provider<NotificationSyncService>((ref) {
  final service = NotificationSyncService();
  // Load persisted blocked packages on startup
  try {
    final box = Hive.box(AppConstants.settingsBox);
    final stored = (box.get('notif_blocked_packages') as List<dynamic>?)
        ?.cast<String>()
        .toList();
    if (stored != null) service.loadFilter(stored);
  } catch (_) {}
  ref.onDispose(() => service.dispose());
  return service;
});

/// Reactive list of blocked package names.
final notifBlockedPackagesProvider =
    StateNotifierProvider<_BlockedPackagesNotifier, Set<String>>(
  (ref) => _BlockedPackagesNotifier(ref.read(notificationSyncServiceProvider)),
);

class _BlockedPackagesNotifier extends StateNotifier<Set<String>> {
  final NotificationSyncService _service;

  _BlockedPackagesNotifier(this._service)
      : super(Set.unmodifiable(_service.blockedPackages));

  void block(String pkg) {
    _service.blockPackage(pkg);
    state = Set.unmodifiable(_service.blockedPackages);
  }

  void unblock(String pkg) {
    _service.unblockPackage(pkg);
    state = Set.unmodifiable(_service.blockedPackages);
  }
}

/// Reactive set of device IDs with sync disabled.
final notifDisabledDevicesProvider =
    StateNotifierProvider<_DisabledDevicesNotifier, Set<String>>(
  (ref) => _DisabledDevicesNotifier(ref.read(notificationSyncServiceProvider)),
);

class _DisabledDevicesNotifier extends StateNotifier<Set<String>> {
  final NotificationSyncService _service;

  _DisabledDevicesNotifier(this._service) : super({});

  void disableForDevice(String id) {
    _service.disableSyncForDevice(id);
    state = {...state, id};
  }

  void enableForDevice(String id) {
    _service.enableSyncForDevice(id);
    state = state.where((d) => d != id).toSet();
  }
}
