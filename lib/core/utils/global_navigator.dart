import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/notification/notification_service.dart';

/// Global navigator key for showing dialogs from services.
final globalNavigatorKey = GlobalKey<NavigatorState>();

/// Show a transfer approval dialog, or a notification with Accept/Reject buttons
/// when the app is in the background.
///
/// - App in foreground → in-app dialog (existing behaviour, unchanged)
/// - App in background → notification with Accept / Reject buttons
Future<bool> showTransferApprovalDialog({
  required String fileName,
  required String deviceName,
  required int fileSize,
  String transferId = '',
}) async {
  final context = globalNavigatorKey.currentContext;

  // Detect whether the app is in the foreground.
  // SchedulerBinding.instance.lifecycleState is null before the first frame,
  // which also means we can't show a dialog — fall through to notification.
  final lifecycle = SchedulerBinding.instance.lifecycleState;
  final isForegrounded = lifecycle == AppLifecycleState.resumed;

  if (context != null && isForegrounded) {
    // ── In-app dialog (unchanged existing behaviour) ──────────────────────
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Incoming File'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$deviceName wants to send you a file:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file,
                      color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatBytes(fileSize),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Notification-based approval (app backgrounded / no context) ──────────
  if (transferId.isNotEmpty) {
    return NotificationService.showIncomingFileRequest(
      transferId: transferId,
      fileName: fileName,
      deviceName: deviceName,
      fileSize: fileSize,
    );
  }

  // Fallback: no context and no transferId — auto-accept so transfer isn't lost
  return true;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
