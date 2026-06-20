import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/browser_receiver/browser_receiver_service.dart';

final browserReceiverServiceProvider = Provider<BrowserReceiverService>((ref) {
  final service = BrowserReceiverService();
  ref.onDispose(() => service.dispose());
  return service;
});

final browserReceiverActiveProvider = StateProvider<bool>((ref) => false);
final browserReceiverUrlProvider = StateProvider<String?>((ref) => null);
/// Optional password used for browser receiver sessions.
final browserReceiverPasswordProvider = StateProvider<String?>((ref) => null);
