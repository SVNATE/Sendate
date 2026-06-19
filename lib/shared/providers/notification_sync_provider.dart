import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../services/notification_sync/notification_sync_service.dart';

/// Notification sync enabled toggle (persisted)
final notificationSyncEnabledProvider =
    StateNotifierProvider<NotificationSyncEnabledNotifier, bool>(
  (ref) => NotificationSyncEnabledNotifier(),
);

class NotificationSyncEnabledNotifier extends StateNotifier<bool> {
  NotificationSyncEnabledNotifier() : super(_load());

  static bool _load() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('notification_sync_enabled', defaultValue: true) as bool;
  }

  Future<void> toggle() async {
    state = !state;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('notification_sync_enabled', state);
  }

  Future<void> set(bool value) async {
    state = value;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('notification_sync_enabled', value);
  }
}

/// Notification sync service singleton provider
final notificationSyncServiceProvider = Provider<NotificationSyncService>((ref) {
  final service = NotificationSyncService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream of received notifications from remote devices
final receivedNotificationsStreamProvider =
    StreamProvider<SyncedNotification>((ref) {
  final service = ref.watch(notificationSyncServiceProvider);
  return service.receivedNotifications;
});

/// List of recent synced notifications (kept in memory for the UI)
final syncedNotificationsProvider =
    StateNotifierProvider<SyncedNotificationsNotifier, List<SyncedNotification>>(
  (ref) {
    final notifier = SyncedNotificationsNotifier();

    // Listen to incoming notifications stream
    ref.listen(receivedNotificationsStreamProvider, (_, next) {
      next.whenData((notification) {
        notifier.addNotification(notification);
      });
    });

    return notifier;
  },
);

class SyncedNotificationsNotifier extends StateNotifier<List<SyncedNotification>> {
  SyncedNotificationsNotifier() : super([]);

  static const _maxNotifications = 100;

  void addNotification(SyncedNotification notification) {
    state = [notification, ...state].take(_maxNotifications).toList();
  }

  void removeNotification(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void clear() {
    state = [];
  }
}
