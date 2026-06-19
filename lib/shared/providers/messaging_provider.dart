import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/messaging/messaging_service.dart';

final messagingServiceProvider = Provider<MessagingService>((ref) {
  final service = MessagingService();
  ref.onDispose(() => service.dispose());
  return service;
});
