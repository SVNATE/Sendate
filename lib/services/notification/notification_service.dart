import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification service with persistent connection notification + action buttons.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _connectionChannelId = 'sendate_connection';
  static const _transferChannelId = 'sendate_transfer';
  static const _clipboardChannelId = 'sendate_clipboard';

  static const connectionNotifId = 1;
  static const transferNotifId = 100;
  static const clipboardNotifId = 200;

  /// Initialize notifications
  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationAction,
    );

    // Create notification channels (Android)
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _connectionChannelId,
        'Connection Status',
        description: 'Shows connected devices',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _transferChannelId,
        'File Transfers',
        description: 'Transfer progress and completion',
        importance: Importance.high,
      ));
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _clipboardChannelId,
        'Clipboard',
        description: 'Clipboard sync notifications',
        importance: Importance.defaultImportance,
        playSound: false,
      ));
    }
  }

  /// Show persistent "Connected to:" notification with action buttons
  static Future<void> showConnectionNotification({
    required String deviceName,
    required int connectedCount,
  }) async {
    final title = connectedCount > 1
        ? 'Connected to $connectedCount devices'
        : 'Connected to: $deviceName';

    await _plugin.show(
      connectionNotifId,
      title,
      'Tap to open Sendate',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _connectionChannelId,
          'Connection Status',
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          importance: Importance.low,
          priority: Priority.low,
          actions: [
            const AndroidNotificationAction(
              'send_clipboard',
              'Send Clipboard',
              showsUserInterface: true,
            ),
            const AndroidNotificationAction(
              'send_files',
              'Send Files',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Remove connection notification
  static Future<void> removeConnectionNotification() async {
    await _plugin.cancel(connectionNotifId);
  }

  /// Show clipboard received notification
  static Future<void> showClipboardReceived({
    required String senderName,
    required String textPreview,
  }) async {
    final preview = textPreview.length > 50 ? '${textPreview.substring(0, 50)}...' : textPreview;

    await _plugin.show(
      clipboardNotifId,
      'Clipboard from $senderName',
      preview,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _clipboardChannelId,
          'Clipboard',
          playSound: false,
          autoCancel: true,
          actions: [
            const AndroidNotificationAction('copy', 'Copy', showsUserInterface: false),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Show transfer complete notification
  static Future<void> showTransferComplete({
    required String fileName,
    required String deviceName,
    required bool isSend,
  }) async {
    await _plugin.show(
      transferNotifId + DateTime.now().millisecondsSinceEpoch % 100,
      isSend ? 'Sent to $deviceName' : 'Received from $deviceName',
      fileName,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _transferChannelId,
          'File Transfers',
          actions: [
            if (!isSend) const AndroidNotificationAction('open', 'Open', showsUserInterface: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Show transfer failed notification
  static Future<void> showTransferFailed({
    required String fileName,
    required String error,
  }) async {
    await _plugin.show(
      transferNotifId + DateTime.now().millisecondsSinceEpoch % 100,
      'Transfer failed',
      '$fileName: $error',
      const NotificationDetails(
        android: AndroidNotificationDetails(_transferChannelId, 'File Transfers'),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Handle notification action taps
  static void _onNotificationAction(NotificationResponse response) {
    final actionId = response.actionId;

    switch (actionId) {
      case 'send_clipboard':
        // Will be handled by the app when it opens
        _pendingAction = NotificationAction.sendClipboard;
      case 'send_files':
        _pendingAction = NotificationAction.sendFiles;
      case 'copy':
        // Clipboard already set by the clipboard service
        break;
      case 'open':
        _pendingAction = NotificationAction.openFile;
    }
  }

  /// Pending action from notification tap (consumed by UI)
  static NotificationAction? _pendingAction;
  static NotificationAction? consumePendingAction() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }
}

enum NotificationAction { sendClipboard, sendFiles, openFile }
