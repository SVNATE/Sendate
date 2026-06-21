import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification service with persistent connection notification + action buttons.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _connectionChannelId = 'sendate_connection';
  static const _transferChannelId = 'sendate_transfer';
  static const _transferProgressChannelId = 'sendate_transfer_progress';
  static const _clipboardChannelId = 'sendate_clipboard';
  static const _incomingRequestChannelId = 'sendate_incoming_request';

  static const connectionNotifId = 1;
  static const transferNotifId = 100;   // send-batch summary (always replaces previous)
  // Receive notifications: 101–199 (timestamp-bucketed, stack)
  static const clipboardNotifId = 200;
  // Progress notifications: 300 + abs(transferId.hashCode) % 400  → 300–699
  // Incoming request notifications: 700 + abs(transferId.hashCode) % 200 → 700–899

  static int _receiveNotifId() => 101 + DateTime.now().millisecondsSinceEpoch % 99;

  /// Pending incoming-file approvals keyed by transferId.
  /// Completed when the user taps Accept or Reject in the notification.
  static final Map<String, Completer<bool>> _pendingApprovals = {};

  /// Optional callback when the user requests a cancel from a send-progress notification.
  static void Function(String transferId)? onCancelTransferRequested;

  /// Last time a progress notification was updated, per transferId.
  static final Map<String, DateTime> _lastProgressUpdate = {};

  static int _progressNotifId(String transferId) =>
      300 + transferId.hashCode.abs() % 400;

  static int _requestNotifId(String transferId) =>
      700 + transferId.hashCode.abs() % 200;

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
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _transferProgressChannelId,
        'Transfer Progress',
        description: 'Shows ongoing file send/receive progress in status bar',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));
      await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
        _incomingRequestChannelId,
        'Incoming File Requests',
        description: 'Accept or reject incoming file transfers',
        importance: Importance.high,
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

  /// Show/update an ongoing send-progress notification in the status bar.
  /// Call this each time progress changes. Throttled internally to max once/500ms.
  static Future<void> showTransferSending({
    required String transferId,
    required String fileName,
    required String deviceName,
    required int progressPercent, // 0–100
    required int bytesTransferred,
    required int totalBytes,
    required int speedBps,
  }) async {
    if (!Platform.isAndroid) return;

    // Throttle: skip update if last one was <500ms ago
    final now = DateTime.now();
    final last = _lastProgressUpdate[transferId];
    if (last != null && now.difference(last).inMilliseconds < 500 && progressPercent < 100) {
      return;
    }
    _lastProgressUpdate[transferId] = now;

    final speedLabel = _formatSpeed(speedBps);
    final subtitle = '$deviceName • $speedLabel';

    await _plugin.show(
      _progressNotifId(transferId),
      'Sending $fileName',
      subtitle,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _transferProgressChannelId,
          'Transfer Progress',
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          showProgress: true,
          maxProgress: 100,
          progress: progressPercent,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          actions: [
            AndroidNotificationAction(
              'cancel_transfer',
              'Cancel',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: transferId,
    );
  }

  /// Cancel the ongoing send-progress notification for a given transferId.
  static Future<void> cancelTransferProgress(String transferId) async {
    _lastProgressUpdate.remove(transferId);
    await _plugin.cancel(_progressNotifId(transferId));
  }

  /// Show an incoming file request notification with Accept / Reject buttons.
  /// Returns a [Future<bool>] that completes when the user responds.
  /// If the user dismisses the notification without tapping, returns false after timeout.
  static Future<bool> showIncomingFileRequest({
    required String transferId,
    required String fileName,
    required String deviceName,
    required int fileSize,
  }) async {
    if (!Platform.isAndroid) return true; // Non-Android: auto-accept (dialog handles it)

    final completer = Completer<bool>();
    _pendingApprovals[transferId] = completer;

    final sizeLabel = _formatBytes(fileSize);

    await _plugin.show(
      _requestNotifId(transferId),
      '$deviceName wants to send a file',
      '$fileName • $sizeLabel',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _incomingRequestChannelId,
          'Incoming File Requests',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: false,
          playSound: true,
          actions: [
            const AndroidNotificationAction(
              'accept_file',
              'Accept',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'reject_file',
              'Reject',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: transferId,
    );

    // Safety timeout: if user does not respond within 60 s, auto-reject
    Future.delayed(const Duration(seconds: 60), () {
      if (!completer.isCompleted) {
        _pendingApprovals.remove(transferId);
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Cancel a pending incoming file request notification (e.g. transfer was cancelled by sender).
  static Future<void> cancelIncomingRequest(String transferId) async {
    final completer = _pendingApprovals.remove(transferId);
    if (completer != null && !completer.isCompleted) completer.complete(false);
    await _plugin.cancel(_requestNotifId(transferId));
  }

  /// Show a single summary notification after a send batch finishes.
  /// Shows one notification regardless of how many files were in the batch.
  static Future<void> showSendBatchComplete({
    required String deviceName,
    required List<String> sentFiles,
    required List<String> failedFiles,
  }) async {
    final success = sentFiles.length;
    final failed = failedFiles.length;
    final total = success + failed;
    if (total == 0) return;

    final String title;
    final String body;
    if (failed == 0) {
      title = total == 1 ? 'Sent to $deviceName' : 'Sent $total files to $deviceName';
      body = sentFiles.join(', ');
    } else if (success == 0) {
      title = total == 1 ? 'Failed to send' : 'Send failed';
      body = total == 1 ? failedFiles.first : '$total files could not be sent to $deviceName';
    } else {
      title = '$success of $total sent to $deviceName';
      body = '$failed file${failed > 1 ? 's' : ''} failed';
    }

    await _plugin.show(
      transferNotifId, // fixed ID → replaces previous summary
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _transferChannelId,
          'File Transfers',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Show a receive-side notification when a file arrives (TCP or browser).
  static Future<void> showFileReceived({
    required String fileName,
    required String senderName,
    required int fileSize,
  }) async {
    await _plugin.show(
      _receiveNotifId(),
      'Received from $senderName',
      '$fileName • ${_formatBytes(fileSize)}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _transferChannelId,
          'File Transfers',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            const AndroidNotificationAction('open', 'Open', showsUserInterface: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Handle notification action taps
  static void _onNotificationAction(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload ?? '';

    switch (actionId) {
      case 'send_clipboard':
        _pendingAction = NotificationAction.sendClipboard;
      case 'send_files':
        _pendingAction = NotificationAction.sendFiles;
      case 'copy':
        // Clipboard already set by the clipboard service
        break;
      case 'open':
        _pendingAction = NotificationAction.openFile;
      case 'accept_file':
        // User accepted an incoming file request shown as notification
        final completer = _pendingApprovals.remove(payload);
        if (completer != null && !completer.isCompleted) completer.complete(true);
      case 'reject_file':
        // User rejected an incoming file request shown as notification
        final completer = _pendingApprovals.remove(payload);
        if (completer != null && !completer.isCompleted) completer.complete(false);
      case 'cancel_transfer':
        // User tapped Cancel on the send-progress notification
        if (payload.isNotEmpty) {
          onCancelTransferRequested?.call(payload);
        }
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatSpeed(int bps) {
  if (bps <= 0) return '';
  if (bps < 1024) return '$bps B/s';
  if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
  return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}
