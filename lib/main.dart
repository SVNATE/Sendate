import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/global_navigator.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/settings/presentation/screens/app_lock_screen.dart';
import 'services/device/device_identity_service.dart';
import 'services/expiry/transfer_expiry_service.dart';
import 'services/foreground/android_foreground_service.dart';
import 'services/background/system_tray_service.dart';
import 'services/network/connectivity_monitor.dart';
import 'services/notification/notification_service.dart';
import 'shared/models/device_model.dart';
import 'shared/providers/clipboard_provider.dart';
import 'shared/providers/connection_provider.dart';
import 'shared/providers/device_provider.dart';
import 'shared/providers/discovery_provider.dart';
import 'shared/providers/messaging_provider.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/transfer_service_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.settingsBox);
  await Hive.openBox(AppConstants.devicesBox);
  await Hive.openBox(AppConstants.historyBox);
  await Hive.openBox(AppConstants.resumeBox);
  await Hive.openBox(AppConstants.blockedBox);

  // Initialize device identity
  final identityService = DeviceIdentityService();
  final settingsBox = Hive.box(AppConstants.settingsBox);
  final storedId = settingsBox.get('device_id') as String?;
  final storedName = settingsBox.get('device_name') as String?;

  final device = await identityService.getDeviceIdentity(
    storedId: storedId,
    storedName: storedName,
  );

  // Persist device ID if new
  if (storedId == null) {
    await settingsBox.put('device_id', device.id);
  }
  if (storedName == null) {
    await settingsBox.put('device_name', device.name);
  }

  // Cleanup expired files on startup
  final expiryService = TransferExpiryService();
  await expiryService.cleanupExpired();

  // Initialize notifications
  try {
    await NotificationService.init();
  } catch (_) {}

  // Background service disabled — causes crash on Android 14+ without proper foreground service type
  // The app works fine without it: discovery and clipboard run while app is open
  // try {
  //   await BackgroundServiceHelper.initialize();
  // } catch (_) {}

  // Start Android foreground service (KDE Connect style)
  if (AndroidForegroundService.isSupported) {
    await AndroidForegroundService.instance.start();
  }

  // Initialize system tray (macOS/Windows/Linux)
  SystemTrayService? trayService;
  try {
    trayService = SystemTrayService.instance;
    await trayService.init();
    trayService.onOpenApp = () async {};
    trayService.onQuit = () => exit(0);
  } catch (_) {
    trayService = null;
  }

  runApp(
    ProviderScope(
      overrides: [
        currentDeviceProvider.overrideWith((ref) => device),
      ],
      child: const SendateApp(),
    ),
  );
}

class SendateApp extends ConsumerStatefulWidget {
  const SendateApp({super.key});

  @override
  ConsumerState<SendateApp> createState() => _SendateAppState();
}

class _SendateAppState extends ConsumerState<SendateApp> {
  bool _isLocked = false;
  bool _showOnboarding = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTransferServer();
      // Start discovery ALWAYS, regardless of other service errors
      _startDiscovery();

      final settingsBox = Hive.box(AppConstants.settingsBox);
      final onboardingDone = settingsBox.get('onboarding_complete', defaultValue: false) as bool;
      final lockEnabled = ref.read(appLockEnabledProvider);

      setState(() {
        _showOnboarding = !onboardingDone;
        _isLocked = lockEnabled && onboardingDone;
        _initialized = true;
      });
    });
  }

  void _startDiscovery() {
    try {
      ref.read(discoveryControllerProvider).startDiscovery();

      // Wire tray device-specific actions (Soduto style)
      final tray = SystemTrayService.instance;
      tray.onSendClipboardToDevice = (deviceName) {
        final devices = ref.read(allNearbyDevicesProvider);
        final device = devices.where((d) => d.name == deviceName).firstOrNull;
        if (device != null) {
          ref.read(clipboardSyncServiceProvider).sendClipboardTo(device);
        }
      };
      tray.onSendFilesToDevice = (deviceName) async {
        final devices = ref.read(allNearbyDevicesProvider);
        final device = devices.where((d) => d.name == deviceName).firstOrNull;
        if (device != null) {
          try {
            final result = await FilePicker.platform.pickFiles(allowMultiple: true);
            if (result != null && result.files.isNotEmpty) {
              final filePaths = result.files
                  .where((f) => f.path != null)
                  .map((f) => f.path!)
                  .toList();
              if (filePaths.isNotEmpty) {
                ref.read(transferControllerProvider).sendFiles(
                  filePaths: filePaths,
                  target: device,
                );
              }
            }
          } catch (_) {}
        }
      };

      // Wire Android foreground service notification action buttons (KDE Connect style)
      if (AndroidForegroundService.isSupported) {
        final fgService = AndroidForegroundService.instance;
        fgService.onSendClipboardAction = () {
          final clipService = ref.read(clipboardSyncServiceProvider);
          final devices = ref.read(allNearbyDevicesProvider);
          if (devices.isNotEmpty) {
            // Send clipboard to all connected devices
            for (final device in devices) {
              clipService.sendClipboardTo(device);
            }
          } else {
            // Fallback: try trusted devices from storage
            final trustedDevices = ref.read(trustedDevicesProvider);
            for (final device in trustedDevices) {
              if (device.ipAddress != null) {
                clipService.sendClipboardTo(device);
              }
            }
          }
        };
        fgService.onSendFilesAction = () async {
          // Open file picker directly (no navigation needed)
          try {
            final result = await FilePicker.platform.pickFiles(
              allowMultiple: true,
            );
            if (result != null && result.files.isNotEmpty) {
              // Try nearby devices first, then trusted devices
              var devices = ref.read(allNearbyDevicesProvider);
              if (devices.isEmpty) {
                devices = ref.read(trustedDevicesProvider);
              }
              final device = devices.firstOrNull;
              if (device != null) {
                final filePaths = result.files
                    .where((f) => f.path != null)
                    .map((f) => f.path!)
                    .toList();
                if (filePaths.isNotEmpty) {
                  ref.read(transferControllerProvider).sendFiles(
                    filePaths: filePaths,
                    target: device,
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('File picker error: $e');
          }
        };
        // Check if there's a pending action from notification tap while app was backgrounded
        fgService.checkPendingAction();
      }

      // Auto-start clipboard sync when devices are found
      ref.read(discoveryServiceProvider).devicesStream.listen((devices) {
        if (devices.isNotEmpty) {
          final clipService = ref.read(clipboardSyncServiceProvider);
          // Always update known devices so clipboard can reach them via TCP fallback
          clipService.updateKnownDevices(devices);
          if (!clipService.isAutoSyncEnabled && ref.read(clipboardAutoSyncProvider)) {
            clipService.startAutoSync();
          }
        }

        // Update Android foreground notification with device names (KDE Connect style)
        if (AndroidForegroundService.isSupported) {
          AndroidForegroundService.instance.updateConnectedDevices(
            devices.map((d) => d.name).toList(),
          );
        }
      });
    } catch (e) {
      debugPrint('Discovery start error: $e');
    }
  }

  void _initTransferServer() {
    try {
      final service = ref.read(transferServiceProvider);

      // Set local device identity so the sender includes it in the transfer header
      final currentDevice = ref.read(currentDeviceProvider);
      if (currentDevice != null) {
        service.localDeviceId = currentDevice.id;
        service.localDeviceName = currentDevice.name;
      }

      service.onTransferRequest = (transfer) async {
        final autoAccept = ref.read(autoAcceptProvider);
        final trustedDevices = ref.read(trustedDevicesProvider);
        final blockedDevices = ref.read(blockedDevicesProvider);

        // transfer.deviceId is now the sender's actual device ID (from header)
        // or falls back to IP address for older protocol versions.
        // Check against both device ID and IP address for compatibility.
        final senderIp = transfer.deviceId;

        if (blockedDevices.contains(senderIp)) return false;

        // Auto-accept from trusted devices — no approval dialog needed
        final isTrusted = trustedDevices.any((d) =>
            d.id == senderIp ||
            d.ipAddress == senderIp ||
            d.name == transfer.deviceName);
        if (isTrusted) return true;

        // Also auto-accept if the global auto-accept toggle is on
        if (autoAccept) return true;

        return showTransferApprovalDialog(
          fileName: transfer.fileName,
          deviceName: transfer.deviceName,
          fileSize: transfer.fileSize,
        );
      };

      service.startServer();

      final clipboardService = ref.read(clipboardSyncServiceProvider);
      clipboardService.startServer(AppConstants.transferPort);
      if (ref.read(clipboardAutoSyncProvider)) {
        clipboardService.startAutoSync();
      }

      ref.read(persistentConnectionProvider).start();

      // Start message server for offline messaging
      final msgService = ref.read(messagingServiceProvider);
      msgService.startMessageServer(AppConstants.transferPort);

      final connectivityMonitor = ConnectivityMonitor();
      connectivityMonitor.start();
      connectivityMonitor.networkChanges.listen((event) {
        if (event.type == NetworkChangeType.wifiConnected) {
          ref.read(discoveryControllerProvider).restartDiscovery();
        }
      });

      // Auto-connect to trusted discovered devices for clipboard sync
      // + Update system tray with device names
      ref.read(discoveryServiceProvider).devicesStream.listen((devices) {
        final trusted = ref.read(trustedDevicesProvider);
        final conn = ref.read(persistentConnectionProvider);
        final clipService = ref.read(clipboardSyncServiceProvider);

        // Keep clipboard service aware of all reachable devices
        clipService.updateKnownDevices(devices);

        for (final device in devices) {
          if (trusted.any((t) => t.id == device.id) && !conn.isConnected(device.id)) {
            conn.connectToDevice(device);
          }
        }
        // Update tray menu with discovered device names
        SystemTrayService.instance.updateConnectedDevices(
          devices.map((d) => d.name).toList(),
        );
      });

      // Clipboard received silently — no pop-up notification needed
      // (content is already written to system clipboard by ClipboardSyncService)
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    // Show router immediately (onboarding/lock handled after first frame)
    if (!_initialized) {
      return MaterialApp.router(
        title: 'Sendate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: appRouter,
      );
    }

    if (_showOnboarding) {
      return MaterialApp(
        title: 'Sendate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: OnboardingScreen(onComplete: () => setState(() {
          _showOnboarding = false;
        })),
      );
    }

    if (_isLocked) {
      return MaterialApp(
        title: 'Sendate',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: AppLockScreen(onUnlocked: () => setState(() => _isLocked = false)),
      );
    }

    return MaterialApp.router(
      title: 'Sendate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
