import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../shared/models/transfer_model.dart';
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
  Stream<TransferModel>? transferStream,
}) async {
  final context = globalNavigatorKey.currentContext;

  // Detect whether the app is in the foreground.
  // SchedulerBinding.instance.lifecycleState is null before the first frame,
  // which also means we can't show a dialog — fall through to notification.
  final lifecycle = SchedulerBinding.instance.lifecycleState;
  final isForegrounded = lifecycle == AppLifecycleState.resumed;

  if (context != null && isForegrounded) {
    // ── In-app dialog (unchanged existing behaviour) ──────────────────────
    bool dialogClosed = false;
    StreamSubscription? subscription;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        if (transferStream != null) {
          subscription ??= transferStream.listen((model) {
            if (model.id == transferId && (model.state == TransferState.failed || model.state == TransferState.cancelled)) {
              if (!dialogClosed) {
                dialogClosed = true;
                Navigator.of(ctx).pop(false);
              }
            }
          });
        }
        
        final colorScheme = Theme.of(ctx).colorScheme;
        final isBatch = batchFileCount != null && batchFileCount > 1;
        
        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Animated pulsing icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.arrowDownToLine, 
                          size: 40, 
                          color: colorScheme.primary
                        ),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scale(duration: 1.seconds, begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1)),
                  
                  const SizedBox(height: 48),
                  
                  // Device Name
                  Text(
                    deviceName,
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, curve: Curves.easeOutQuad),
                  
                  const SizedBox(height: 16),
                  Text(
                    isBatch ? 'wants to send you $batchFileCount files' : 'wants to send you a file',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ).animate().fadeIn(delay: 100.ms, duration: 400.ms).slideY(begin: 0.2, curve: Curves.easeOutQuad),
                  
                  const SizedBox(height: 48),
                  
                  // File Info Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(isBatch ? LucideIcons.files : LucideIcons.fileText, color: colorScheme.primary, size: 32),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isBatch ? '$batchFileCount Files' : fileName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatBytes(fileSize),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms).slideY(begin: 0.2, curve: Curves.easeOutQuad),
                  
                  const Spacer(flex: 3),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () {
                            if (!dialogClosed) {
                              dialogClosed = true;
                              Navigator.pop(ctx, false);
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                            foregroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.x, size: 24),
                              const SizedBox(width: 12),
                              Text(
                                'Decline',
                                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.2),
                      
                      const SizedBox(width: 16),
                      
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (!dialogClosed) {
                              dialogClosed = true;
                              Navigator.pop(ctx, true);
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            elevation: 4,
                            shadowColor: Colors.green.withValues(alpha: 0.4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.check, size: 24),
                              const SizedBox(width: 12),
                              Text(
                                'Accept',
                                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.2),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
    );
    
    await subscription?.cancel();
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
