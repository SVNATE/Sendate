import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../models/transfer_model.dart';
import '../providers/transfer_provider.dart';
import '../providers/transfer_service_provider.dart';

class ActiveTransfersSheet extends ConsumerWidget {
  const ActiveTransfersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(activeTransfersProvider);

    if (transfers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  'Transfers',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Gap(8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.transferActive.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${transfers.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.transferActive,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...transfers.map(
            (t) => _TransferItem(transfer: t),
          ),
          const Gap(8),
        ],
      ),
    );
  }
}

class _TransferItem extends ConsumerWidget {
  final TransferModel transfer;

  const _TransferItem({required this.transfer});

  Color get _stateColor => switch (transfer.state) {
        TransferState.sending || TransferState.receiving => AppColors.transferActive,
        TransferState.paused => AppColors.transferPaused,
        TransferState.retrying => AppColors.warning,
        TransferState.completed => AppColors.transferComplete,
        TransferState.failed || TransferState.cancelled => AppColors.transferFailed,
        _ => AppColors.transferActive,
      };

  String get _stateLabel => switch (transfer.state) {
        TransferState.queued => 'Queued',
        TransferState.connecting => 'Connecting...',
        TransferState.waitingApproval => 'Waiting...',
        TransferState.sending => 'Sending',
        TransferState.receiving => 'Receiving',
        TransferState.paused => 'Paused',
        TransferState.retrying => 'Retrying',
        _ => transfer.state.name,
      };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(transferControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isPausable = transfer.state == TransferState.sending;
    final isResumable = transfer.state == TransferState.paused;
    final isCancellable = transfer.state == TransferState.sending ||
        transfer.state == TransferState.paused ||
        transfer.state == TransferState.connecting ||
        transfer.state == TransferState.waitingApproval;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Direction icon
              Icon(
                transfer.direction == TransferDirection.sent
                    ? LucideIcons.arrowUpRight
                    : LucideIcons.arrowDownLeft,
                size: 14,
                color: _stateColor,
              ),
              const Gap(8),
              // File name
              Expanded(
                child: Text(
                  transfer.fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // State label
              Text(
                _stateLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _stateColor,
                ),
              ),
              const Gap(8),
              // Controls
              if (isPausable)
                _ControlButton(
                  icon: LucideIcons.pause,
                  onTap: () => controller.pause(transfer.id),
                ),
              if (isResumable)
                _ControlButton(
                  icon: LucideIcons.play,
                  onTap: () => controller.resume(transfer.id),
                ),
              if (isCancellable)
                _ControlButton(
                  icon: LucideIcons.x,
                  onTap: () => controller.cancel(transfer.id),
                  color: AppColors.error,
                ),
            ],
          ),
          const Gap(6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: transfer.progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(_stateColor),
              minHeight: 3,
            ),
          ),
          const Gap(4),
          // Stats
          Row(
            children: [
              Text(
                '${(transfer.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (transfer.speed != null && transfer.speed! > 0)
                Text(
                  '${_formatBytes(transfer.speed!)}/s',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
