import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
  required String transferId,
  int? batchFileCount,
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
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.download, size: 32, color: colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  batchFileCount != null && batchFileCount > 1 ? 'Incoming Batch' : 'Incoming File',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    text: deviceName,
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary),
                    children: [
                      TextSpan(
                        text: batchFileCount != null && batchFileCount > 1 
                            ? ' wants to send you $batchFileCount files.' 
                            : ' wants to send you a file.',
                        style: TextStyle(fontWeight: FontWeight.normal, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 15),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.fileText, color: colorScheme.primary, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              batchFileCount != null && batchFileCount > 1 
                                  ? '$batchFileCount Files' 
                                  : fileName,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatBytes(fileSize),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: colorScheme.error,
                        ),
                        child: Text(
                          'Reject',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          'Accept',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  // ── Notification-based approval (app backgrounded / no context) ──────────
  if (transferId.isNotEmpty) {
    return NotificationService.showIncomingFileRequest(
      transferId: transferId,
      fileName: batchFileCount != null && batchFileCount > 1 ? '$batchFileCount files' : fileName,
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

/// Show a prompt to ask the user if they want to convert a received .mov file to .mp4
Future<bool> showConversionPrompt(String fileName) async {
  final context = globalNavigatorKey.currentContext;

  final lifecycle = SchedulerBinding.instance.lifecycleState;
  final isForegrounded = lifecycle == AppLifecycleState.resumed;

  if (context != null && isForegrounded) {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Incompatible Format'),
        content: Text(
          "You received '$fileName', which is a .mov file. Older Android devices may not be able to play this format.\n\n"
          "Do you want to convert this .mov file to .mp4?"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // If app is not foregrounded, we default to false (or could use a notification, but for now false to avoid blocking)
  return false;
}
