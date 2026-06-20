import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('History'),
            actions: [
              IconButton(
                onPressed: () => showHelpGuide(context, title: 'History Help', items: historyGuideItems),
                icon: Icon(LucideIcons.helpCircle),
                tooltip: 'Help',
              ),
              if (history.isNotEmpty)
                IconButton(
                  onPressed: () => _confirmClear(context, ref),
                  icon: Icon(LucideIcons.trash2),
                  tooltip: 'Clear history',
                ),
            ],
          ),
          if (history.isEmpty)
            SliverFillRemaining(child: _EmptyHistory())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: history.length,
                itemBuilder: (context, index) => _HistoryTile(
                  transfer: history[index],
                  onTap: () => _showDetail(context, ref, history[index]),
                  onDelete: () {
                    ref
                        .read(transferHistoryProvider.notifier)
                        .removeRecord(history[index].id);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'This will remove all transfer records. Files on disk are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(transferHistoryProvider.notifier).clear();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, TransferModel transfer) {
    final bool canResend = transfer.direction == TransferDirection.sent &&
        (transfer.state == TransferState.failed ||
            transfer.state == TransferState.cancelled) &&
        File(transfer.filePath).existsSync();

    final bool failedReceive = transfer.direction == TransferDirection.received &&
        (transfer.state == TransferState.failed ||
            transfer.state == TransferState.cancelled);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transfer.fileName,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Gap(16),
              _DetailRow('Device', transfer.deviceName),
              _DetailRow('Size', _formatBytes(transfer.fileSize)),
              _DetailRow(
                'Direction',
                transfer.direction == TransferDirection.sent
                    ? 'Sent'
                    : 'Received',
              ),
              _DetailRow('Status', transfer.state.name),
              if (transfer.speed != null)
                _DetailRow('Speed', '${_formatBytes(transfer.speed!)}/s'),
              if (transfer.duration != null)
                _DetailRow(
                  'Duration',
                  '${(transfer.duration! / 1000).toStringAsFixed(1)}s',
                ),
              if (transfer.errorMessage != null) ...
                [_DetailRow('Error', transfer.errorMessage!)],
              const Gap(16),
              if (canResend) ...
                [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Resend'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final allDevices = ref.read(allNearbyDevicesProvider);
                        final target = allDevices
                            .where((d) => d.id == transfer.deviceId)
                            .firstOrNull;
                        if (target == null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '${transfer.deviceName} is not available'),
                              ),
                            );
                          }
                          return;
                        }
                        ref.read(transferControllerProvider).sendFiles(
                              filePaths: [transfer.filePath],
                              target: target,
                            );
                      },
                    ),
                  ),
                  const Gap(8),
                ]
              else if (failedReceive) ...
                [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.info,
                            size: 14,
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant),
                        const Gap(8),
                        Expanded(
                          child: Text(
                            'Ask ${transfer.deviceName} to resend this file.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
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

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.clock,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const Gap(16),
          Text(
            'No transfers yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Gap(4),
          Text(
            'Your transfer history will appear here',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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

    return Dismissible(
      key: Key(transfer.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.red),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _stateColor(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _directionIcon,
              color: _stateColor(context),
              size: 20,
            ),
          ),
          title: Text(
            transfer.fileName,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${transfer.deviceName} • ${_formatBytes(transfer.fileSize)}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
        ),
      ),
    );
  }
}
