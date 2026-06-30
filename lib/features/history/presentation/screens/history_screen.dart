import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';

import '../../../../shared/models/sendate_file.dart';
import '../../../../shared/models/transfer_model.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/transfer_provider.dart';
import '../../../../shared/providers/transfer_service_provider.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(transferHistoryProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'History',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => showHelpGuide(context, title: 'History Help', items: historyGuideItems),
                      icon: Icon(LucideIcons.helpCircle, color: colorScheme.onSurfaceVariant),
                      tooltip: 'Help',
                    ),
                    if (history.isNotEmpty)
                      IconButton(
                        onPressed: () => _confirmClear(context, ref),
                        icon: Icon(LucideIcons.trash2, color: colorScheme.onSurfaceVariant),
                        tooltip: 'Clear history',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(16),

          // Content
          Expanded(
            child: history.isEmpty
                ? const _EmptyHistory()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                    itemCount: history.length,
                    itemBuilder: (context, index) => _HistoryTile(
                      transfer: history[index],
                      onTap: () => _showDetail(context, ref, history[index]),
                      onDelete: () {
                        ref.read(transferHistoryProvider.notifier).removeRecord(history[index].id);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 104),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                'Clear History?',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(12),
              Text(
                'This will permanently remove all transfer records from this device. Files on disk are not affected.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        ref.read(transferHistoryProvider.notifier).clear();
                        Navigator.pop(context);
                      },
                      child: Text('Clear', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onError)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _showDetail(BuildContext context, WidgetRef ref, TransferModel transfer) {
    final bool canResend = transfer.direction == TransferDirection.sent &&
        (transfer.state == TransferState.failed || transfer.state == TransferState.cancelled) &&
        File(transfer.filePath).existsSync();

    final bool failedReceive = transfer.direction == TransferDirection.received &&
        (transfer.state == TransferState.failed || transfer.state == TransferState.cancelled);

    final bool canOpen = transfer.state == TransferState.completed && File(transfer.filePath).existsSync();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 104),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    transfer.fileName,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Gap(24),
              _DetailRow('Device', transfer.deviceName),
              _DetailRow('Size', _formatBytes(transfer.fileSize)),
              _DetailRow('Direction', transfer.direction == TransferDirection.sent ? 'Sent' : 'Received'),
              _DetailRow('Status', transfer.state.name),
              if (transfer.speed != null) _DetailRow('Speed', '${_formatBytes(transfer.speed!)}/s'),
              if (transfer.duration != null) _DetailRow('Duration', '${(transfer.duration! / 1000).toStringAsFixed(1)}s'),
              if (transfer.errorMessage != null) ...[
                const Gap(8),
                _DetailRow('Error', transfer.errorMessage!, isError: true),
              ],
              const Gap(32),
              if (canResend) ...[
                FilledButton.icon(
                  icon: const Icon(LucideIcons.refreshCw, size: 20),
                  label: Text('Resend', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final allDevices = ref.read(allNearbyDevicesProvider);
                    final target = allDevices.where((d) => d.id == transfer.deviceId).firstOrNull;
                    if (target == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${transfer.deviceName} is not nearby')),
                        );
                      }
                      return;
                    }
                    final sendateFile = SendateFile(
                      name: transfer.fileName,
                      size: transfer.fileSize,
                      path: transfer.filePath,
                    );
                    ref.read(transferControllerProvider).sendFiles(
                          files: [sendateFile],
                          target: target,
                        );
                  },
                ),
                const Gap(16),
              ] else if (failedReceive) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.info, size: 20, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      const Gap(12),
                      Expanded(
                        child: Text(
                          'Ask ${transfer.deviceName} to resend this file.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(16),
              ],
              if (canOpen) ...[
                if (transfer.filePath.toLowerCase().endsWith('.mov')) ...[
                  StatefulBuilder(
                    builder: (ctx, setSheetState) {
                      var isConverting = false;
                      return FilledButton.icon(
                        icon: isConverting 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(LucideIcons.video, size: 20),
                        label: Text(isConverting ? 'Converting...' : 'Convert to MP4', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          backgroundColor: Colors.purple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: isConverting ? null : () async {
                          setSheetState(() => isConverting = true);
                          final conversionService = ref.read(conversionServiceProvider);
                          final newPath = await conversionService.convertFile(
                            inputPath: transfer.filePath,
                            targetMimeType: 'video/mp4',
                            targetExtension: 'mp4',
                          );
                          
                          if (newPath != transfer.filePath && File(newPath).existsSync()) {
                            final newName = newPath.split(Platform.pathSeparator).last;
                            ref.read(transferHistoryProvider.notifier).updateRecord(transfer.id, (t) {
                              return t.copyWith(
                                filePath: newPath,
                                fileName: newName,
                                mimeType: 'video/mp4',
                              );
                            });
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Successfully converted to MP4!')),
                              );
                            }
                          } else {
                            setSheetState(() => isConverting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to convert video.')),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                  const Gap(16),
                ],
                FilledButton.icon(
                  icon: const Icon(LucideIcons.externalLink, size: 20),
                  label: Text('Open File', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    OpenFilex.open(transfer.filePath);
                  },
                ),
                const Gap(16),
              ],
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Close', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isError;

  const _DetailRow(this.label, this.value, {this.isError = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isError ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.clock,
            size: 80,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const Gap(24),
          Text(
            'No transfers yet',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const Gap(8),
          Text(
            'Your transfer history will appear here',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final TransferModel transfer;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.transfer,
    required this.onTap,
    required this.onDelete,
  });

  IconData get _directionIcon => transfer.direction == TransferDirection.sent
      ? LucideIcons.arrowUpRight
      : LucideIcons.arrowDownLeft;

  Color _stateColor(BuildContext context) => switch (transfer.state) {
        TransferState.completed => const Color(0xFF22C55E),
        TransferState.failed => const Color(0xFFEF4444),
        TransferState.cancelled => const Color(0xFFF59E0B),
        _ => Theme.of(context).colorScheme.primary,
      };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(transfer.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: colorScheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(LucideIcons.trash2, color: colorScheme.error),
        ),
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _stateColor(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _directionIcon,
                color: _stateColor(context),
                size: 24,
              ),
            ),
            title: Text(
              transfer.fileName,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${transfer.deviceName} • ${_formatBytes(transfer.fileSize)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
