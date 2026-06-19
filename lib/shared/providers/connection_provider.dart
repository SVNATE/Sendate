import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/persistent_connection/persistent_connection_service.dart';
import 'clipboard_provider.dart';

/// Persistent connection service singleton
final persistentConnectionProvider = Provider<PersistentConnectionService>((ref) {
  final service = PersistentConnectionService();

  // Wire clipboard service
  service.clipboardService = ref.read(clipboardSyncServiceProvider);

  ref.onDispose(() => service.dispose());
  return service;
});

/// Connection states stream
final connectionStatesProvider = StreamProvider<Map<String, DeviceConnection>>((ref) {
  final service = ref.watch(persistentConnectionProvider);
  return service.connectionStates;
});
