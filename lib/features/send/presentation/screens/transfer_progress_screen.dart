import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/transfer_model.dart';
import '../../../../shared/providers/transfer_provider.dart';
import '../../../../shared/providers/transfer_service_provider.dart';

/// Arguments passed to [TransferProgressScreen] via GoRouter `extra`.
class TransferProgressArgs {
  /// Device IDs to filter transfers by.  Empty list = show all active
  /// transfers (used for broadcast sends to multiple devices).
  final List<String> deviceIds;
  final String deviceName;

  const TransferProgressArgs({
    required this.deviceIds,
    required this.deviceName,
  });
}

/// Full-screen transfer progress view shown immediately after the user
/// initiates a send.  Works identically on Android, iOS, macOS, Windows,
/// and Linux — all data comes from [activeTransfersProvider].
class TransferProgressScreen extends ConsumerStatefulWidget {
  final TransferProgressArgs args;

  const TransferProgressScreen({super.key, required this.args});

  @override
  ConsumerState<TransferProgressScreen> createState() =>
      _TransferProgressScreenState();
}

class _TransferProgressScreenState
    extends ConsumerState<TransferProgressScreen> {
  final Map<String, TransferModel> _trackedTransfers = {};
  late final Stopwatch _stopwatch;
  Timer? _ticker;
  bool _hasAutoPopped = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    // Tick every second so elapsed time updates
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  /// Returns only the transfers that belong to the current batch.
  /// Filters by deviceIds when provided; shows all active transfers for
  /// broadcast sends where deviceIds is empty.
  void _updateTrackedTransfers(List<TransferModel> allActive, List<TransferModel> history) {
    for (final t in allActive) {
      if (widget.args.deviceIds.isEmpty || widget.args.deviceIds.contains(t.deviceId)) {
        _trackedTransfers[t.id] = t;
      }
    }

    for (final id in _trackedTransfers.keys.toList()) {
      if (!allActive.any((t) => t.id == id)) {
        try {
          final completedTransfer = history.firstWhere((t) => t.id == id);
          _trackedTransfers[id] = completedTransfer;
        } catch (_) {
          // Ignore if missing entirely
        }
      }
    }
  }

  List<TransferModel> _getBatch() {
    return _trackedTransfers.values.toList();
  }

  bool _allDone(List<TransferModel> batch) {
    if (batch.isEmpty) return false;
    return batch.every((t) =>
        t.state == TransferState.completed || t.state == TransferState.failed || t.state == TransferState.cancelled);
  }

  void _checkAutoPop(List<TransferModel> batch) {
    if (_hasAutoPopped || batch.isEmpty) return;
    
    if (_allDone(batch)) {
      // Only auto-pop if everything succeeded (no errors/cancellations)
      final allOk = batch.every((t) => t.state == TransferState.completed);
      if (allOk) {
        _hasAutoPopped = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    }
  }

  Future<bool> _onWillPop(List<TransferModel> batch) async {
    final active = batch.where((t) => t.state == TransferState.sending || t.state == TransferState.receiving).toList();

    if (active.isEmpty) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Transfers?'),
        content: const Text('Going back will cancel all ongoing transfers in this batch.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () {
              for (final t in active) {
                ref.read(transferServiceProvider).cancelTransfer(t.id);
              }
              Navigator.of(context).pop(true);
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final allActive = ref.watch(activeTransfersProvider);
    final history = ref.read(transferHistoryProvider);
    _updateTrackedTransfers(allActive, history);
    
    final batch = _getBatch();
    _checkAutoPop(batch);

    final done = _allDone(batch);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop(batch);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(
            done ? 'Transfer Complete' : 'Sending to ${widget.args.deviceName}',
          ),
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () async {
              final shouldPop = await _onWillPop(batch);
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _formatElapsed(_stopwatch.elapsed),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
        body: batch.isEmpty
            ? _LoadingState(deviceName: widget.args.deviceName)
            : done
                ? _DoneState(
                    batch: batch,
                    elapsed: _stopwatch.elapsed,
                    onDone: () => Navigator.of(context).pop(),
                  )
                : _ActiveState(batch: batch),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-states
// ---------------------------------------------------------------------------

class _LoadingState extends StatelessWidget {
  final String deviceName;
  const _LoadingState({required this.deviceName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const Gap(20),
          Text('Connecting to $deviceName…',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ActiveState extends ConsumerWidget {
  final List<TransferModel> batch;
  const _ActiveState({required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Overall progress
    final totalBytes = batch.fold<int>(0, (s, t) => s + t.fileSize);
    final xferBytes = batch.fold<int>(0, (s, t) => s + t.bytesTransferred);
    final overallProgress =
        totalBytes > 0 ? xferBytes / totalBytes : 0.0;

    return CustomScrollView(
      slivers: [
        // Overall summary bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: _OverallProgressBar(
              progress: overallProgress,
              xferBytes: xferBytes,
              totalBytes: totalBytes,
              activeCount: batch
                  .where((t) =>
                      t.state == TransferState.sending ||
                      t.state == TransferState.connecting)
                  .length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          sliver: SliverList.builder(
            itemCount: batch.length,
            itemBuilder: (context, i) =>
                _TransferCard(transfer: batch[i]),
          ),
        ),
        const SliverToBoxAdapter(child: Gap(32)),
      ],
    );
  }
}

class _DoneState extends StatelessWidget {
  final List<TransferModel> batch;
  final Duration elapsed;
  final VoidCallback onDone;

  const _DoneState({
    required this.batch,
    required this.elapsed,
    required this.onDone,
  });

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final completed = batch.where((t) => t.state == TransferState.completed);
    final failed = batch.where((t) => t.state == TransferState.failed);
    final cancelled = batch.where((t) => t.state == TransferState.cancelled);
    final totalBytes =
        completed.fold<int>(0, (s, t) => s + t.bytesTransferred);

    final allOk = failed.isEmpty && cancelled.isEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: allOk
                  ? AppColors.transferComplete.withValues(alpha: 0.15)
                  : AppColors.warning.withValues(alpha: 0.15),
              child: Icon(
                allOk ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                size: 40,
                color: allOk ? AppColors.transferComplete : AppColors.warning,
              ),
            ),
            const Gap(20),
            Text(
              allOk ? 'All files sent!' : 'Transfer finished with issues',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const Gap(12),
            if (completed.isNotEmpty)
              _StatRow(
                icon: LucideIcons.checkCircle2,
                color: AppColors.transferComplete,
                label:
                    '${completed.length} file${completed.length == 1 ? '' : 's'} sent  •  ${_formatBytes(totalBytes)}',
              ),
            if (failed.isNotEmpty)
              _StatRow(
                icon: LucideIcons.xCircle,
                color: AppColors.transferFailed,
                label:
                    '${failed.length} file${failed.length == 1 ? '' : 's'} failed',
              ),
            if (cancelled.isNotEmpty)
              _StatRow(
                icon: LucideIcons.ban,
                color: AppColors.warning,
                label:
                    '${cancelled.length} file${cancelled.length == 1 ? '' : 's'} cancelled',
              ),
            _StatRow(
              icon: LucideIcons.clock,
              color: Theme.of(context).colorScheme.primary,
              label: 'Elapsed ${_formatDuration(elapsed)}',
            ),
            const Gap(32),
            FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(LucideIcons.checkCheck),
              label: const Text('Done'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const Gap(8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

class _OverallProgressBar extends StatelessWidget {
  final double progress;
  final int xferBytes;
  final int totalBytes;
  final int activeCount;

  const _OverallProgressBar({
    required this.progress,
    required this.xferBytes,
    required this.totalBytes,
    required this.activeCount,
  });

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (activeCount > 0)
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.transferActive,
                      ),
                    ),
                    const Gap(6),
                    Text(
                      '$activeCount active',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.transferActive),
                    ),
                  ],
                ),
            ],
          ),
          const Gap(10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor:
                  colorScheme.outlineVariant.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(AppColors.transferActive),
            ),
          ),
          const Gap(8),
          Text(
            '${_fmt(xferBytes)} / ${_fmt(totalBytes)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends ConsumerWidget {
  final TransferModel transfer;

  const _TransferCard({required this.transfer});

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
        TransferState.scanning => 'Scanning…',
        TransferState.connecting => 'Connecting…',
        TransferState.waitingApproval => 'Awaiting approval…',
        TransferState.sending => 'Sending',
        TransferState.receiving => 'Receiving',
        TransferState.paused => 'Paused',
        TransferState.retrying => 'Retrying…',
        TransferState.completed => 'Complete',
        TransferState.failed => 'Failed',
        TransferState.cancelled => 'Cancelled',
        TransferState.resuming => 'Resuming…',
      };

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String? _eta() {
    if (transfer.speed == null || transfer.speed == 0) return null;
    if (transfer.state != TransferState.sending) return null;
    final remaining = transfer.fileSize - transfer.bytesTransferred;
    if (remaining <= 0) return null;
    final secs = (remaining / transfer.speed!).round();
    if (secs < 60) return '${secs}s left';
    return '${(secs / 60).ceil()}m left';
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
        transfer.state == TransferState.queued;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File name + state badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    transfer.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Gap(8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _stateColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
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
            const Gap(10),
            // Progress bar
            if (transfer.state == TransferState.sending ||
                transfer.state == TransferState.paused ||
                transfer.state == TransferState.completed) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: transfer.progress,
                  minHeight: 6,
                  backgroundColor:
                      colorScheme.outlineVariant.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation(_stateColor),
                ),
              ),
              const Gap(6),
            ],
            // Stats row
            Row(
              children: [
                Text(
                  '${_fmt(transfer.bytesTransferred)} / ${_fmt(transfer.fileSize)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                if (transfer.speed != null && transfer.speed! > 0) ...[
                  const Gap(8),
                  Text(
                    '${_fmt(transfer.speed!)}/s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (_eta() != null) ...[
                  const Gap(8),
                  Text(
                    _eta()!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.transferActive,
                        ),
                  ),
                ],
                if (transfer.errorMessage != null) ...[
                  const Gap(8),
                  Expanded(
                    child: Text(
                      transfer.errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.transferFailed,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                // Controls
                if (isPausable)
                  _SmallIconButton(
                    icon: LucideIcons.pauseCircle,
                    tooltip: 'Pause',
                    onTap: () => controller.pause(transfer.id),
                  ),
                if (isResumable)
                  _SmallIconButton(
                    icon: LucideIcons.playCircle,
                    tooltip: 'Resume',
                    onTap: () => controller.resume(transfer.id),
                  ),
                if (isCancellable)
                  _SmallIconButton(
                    icon: LucideIcons.xCircle,
                    tooltip: 'Cancel',
                    color: AppColors.transferFailed,
                    onTap: () => controller.cancel(transfer.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 20,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
