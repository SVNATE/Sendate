import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme/app_colors.dart';
import '../models/transfer_model.dart';

class TransferProgressCard extends StatelessWidget {
  final TransferModel transfer;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  const TransferProgressCard({
    super.key,
    required this.transfer,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  Color get _stateColor => switch (transfer.state) {
        TransferState.sending || TransferState.receiving => AppColors.transferActive,
        TransferState.paused => AppColors.transferPaused,
        TransferState.completed => AppColors.transferComplete,
        TransferState.failed || TransferState.cancelled => AppColors.transferFailed,
        _ => AppColors.transferActive,
      };

  String get _stateLabel => switch (transfer.state) {
        TransferState.queued => 'Queued',
        TransferState.scanning => 'Scanning...',
        TransferState.connecting => 'Connecting...',
        TransferState.waitingApproval => 'Waiting approval',
        TransferState.sending => 'Sending',
        TransferState.receiving => 'Receiving',
        TransferState.paused => 'Paused',
        TransferState.retrying => 'Retrying...',
        TransferState.completed => 'Complete',
        TransferState.failed => 'Failed',
        TransferState.cancelled => 'Cancelled',
        TransferState.resuming => 'Resuming...',
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transfer.fileName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(2),
                      Text(
                        '${transfer.deviceName} • ${_formatBytes(transfer.fileSize)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _stateColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _stateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _stateColor,
                    ),
                  ),
                ),
              ],
            ),
            const Gap(12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: transfer.progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(_stateColor),
                minHeight: 4,
              ),
            ),
            const Gap(8),
            Row(
              children: [
                Text(
                  '${(transfer.progress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (transfer.speed != null) ...[
                  const Spacer(),
                  Text(
                    '${_formatBytes(transfer.speed!)}/s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
