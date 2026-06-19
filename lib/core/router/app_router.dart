import 'package:go_router/go_router.dart';

import '../../core/utils/global_navigator.dart';
import '../../features/connect/presentation/screens/manual_connect_screen.dart';
import '../../features/connect/presentation/screens/qr_scan_screen.dart';
import '../../features/devices/presentation/screens/devices_screen.dart';
import '../../features/history/presentation/screens/history_screen.dart';
import '../../features/messaging/presentation/screens/chat_screen.dart';
import '../../features/receive/presentation/screens/receive_screen.dart';
import '../../features/send/presentation/screens/send_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../shared/models/device_model.dart';
import '../shell/adaptive_shell.dart';

final appRouter = GoRouter(
  navigatorKey: globalNavigatorKey,
  initialLocation: '/receive',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AdaptiveShell(child: child),
      routes: [
        GoRoute(
          path: '/receive',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReceiveScreen(),
          ),
        ),
        GoRoute(
          path: '/send',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SendScreen(),
          ),
        ),
        GoRoute(
          path: '/devices',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DevicesScreen(),
          ),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: HistoryScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
    // Non-shell routes (full screen)
    GoRoute(
      path: '/connect/manual',
      builder: (context, state) => const ManualConnectScreen(),
    ),
    GoRoute(
      path: '/connect/scan',
      builder: (context, state) => const QrScanScreen(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => ChatScreen(
        device: state.extra as DeviceModel,
      ),
    ),
  ],
);
