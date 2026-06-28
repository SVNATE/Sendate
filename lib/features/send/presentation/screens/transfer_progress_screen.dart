import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/transfer_model.dart';
import '../../../../shared/providers/transfer_provider.dart';
import '../../../../shared/providers/transfer_service_provider.dart';

class TransferProgressArgs {
  final List<String> deviceIds;
  final String deviceName;

  const TransferProgressArgs({
    required this.deviceIds,
    required this.deviceName,
  });
}

class TransferProgressScreen extends ConsumerStatefulWidget {
  final TransferProgressArgs args;
  const TransferProgressScreen({super.key, required this.args});

  @override
  ConsumerState<TransferProgressScreen> createState() => _TransferProgressScreenState();
}

class _TransferProgressScreenState extends ConsumerState<TransferProgressScreen> {
  final Map<String, TransferModel> _trackedTransfers = {};
  late final Stopwatch _stopwatch;
  Timer? _ticker;
  bool _hasAutoPopped = false;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
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
        } catch (_) {}
      }
    }
  }

  List<TransferModel> _getBatch() => _trackedTransfers.values.toList();

  bool _allDone(List<TransferModel> batch) {
    if (batch.isEmpty) return false;
    return batch.every((t) =>
        t.state == TransferState.completed || t.state == TransferState.failed || t.state == TransferState.cancelled);
  }

  void _checkAutoPop(List<TransferModel> batch) {
    if (_hasAutoPopped || batch.isEmpty) return;
    if (_allDone(batch)) {
      final allOk = batch.every((t) => t.state == TransferState.completed);
      if (allOk) {
        _hasAutoPopped = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Cancel Transfers?', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text('Going back will cancel all ongoing transfers.', style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('No', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () {
              for (final t in active) {
                ref.read(transferServiceProvider).cancelTransfer(t.id);
              }
              Navigator.of(context).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.transferFailed),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
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
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              // Custom Modern Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () async {
                        final shouldPop = await _onWillPop(batch);
                        if (shouldPop && context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _formatElapsed(_stopwatch.elapsed),
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: batch.isEmpty
                    ? _LoadingState(deviceName: widget.args.deviceName)
                    : done
                        ? _DoneState(
                            batch: batch,
                            elapsed: _stopwatch.elapsed,
                            onDone: () => Navigator.of(context).pop(),
                          )
                        : _ActiveState(batch: batch, deviceName: widget.args.deviceName),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          const Gap(24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Connecting to $deviceName…',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveState extends ConsumerWidget {
  final List<TransferModel> batch;
  final String deviceName;
  const _ActiveState({required this.batch, required this.deviceName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalBytes = batch.fold<int>(0, (s, t) => s + t.fileSize);
    final xferBytes = batch.fold<int>(0, (s, t) => s + t.bytesTransferred);
    final overallProgress = totalBytes > 0 ? xferBytes / totalBytes : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sending to',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    deviceName,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const Gap(48),
                _MassiveProgressHero(
                  progress: overallProgress,
                  xferBytes: xferBytes,
                  totalBytes: totalBytes,
                ),
                const Gap(48),
                Text(
                  'Files',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Gap(16),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList.builder(
            itemCount: batch.length,
            itemBuilder: (context, i) => _TransferCard(transfer: batch[i]),
          ),
        ),
        const SliverToBoxAdapter(child: Gap(48)),
      ],
    );
  }
}

class _MassiveProgressHero extends StatelessWidget {
  final double progress;
  final int xferBytes;
  final int totalBytes;

  const _MassiveProgressHero({
    required this.progress,
    required this.xferBytes,
    required this.totalBytes,
  });

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (progress * 100).toStringAsFixed(0),
                style: GoogleFonts.outfit(
                  fontSize: 80,
                  fontWeight: FontWeight.w800,
                  height: 0.9,
                  letterSpacing: -3,
                  color: colorScheme.primary,
                ),
              ),
              const Gap(8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '%',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Gap(24),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_fmt(xferBytes)} / ${_fmt(totalBytes)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Gap(24),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
          ),
        ),
        const Gap(12),
        Text(
          '${_fmt(xferBytes)} of ${_fmt(totalBytes)}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  transfer.fileName,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Gap(12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _stateLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _stateColor,
                  ),
                ),
              ),
            ],
          ),
          const Gap(16),
          if (transfer.state == TransferState.sending ||
              transfer.state == TransferState.paused ||
              transfer.state == TransferState.completed) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: transfer.progress,
                minHeight: 4,
                backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation(_stateColor),
              ),
            ),
            const Gap(12),
          ],
          Row(
            children: [
              Text(
                '${_fmt(transfer.bytesTransferred)} / ${_fmt(transfer.fileSize)}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (transfer.speed != null && transfer.speed! > 0) ...[
                const Gap(12),
                Text(
                  '•',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const Gap(12),
                Text(
                  '${_fmt(transfer.speed!)}/s',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_eta() != null) ...[
                const Gap(12),
                Text(
                  '•',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const Gap(12),
                Text(
                  _eta()!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
              const Spacer(),
              if (isPausable)
                _SmallIconButton(
                  icon: LucideIcons.pauseCircle,
                  onTap: () => controller.pause(transfer.id),
                ),
              if (isResumable)
                _SmallIconButton(
                  icon: LucideIcons.playCircle,
                  onTap: () => controller.resume(transfer.id),
                ),
              if (isCancellable)
                _SmallIconButton(
                  icon: LucideIcons.xCircle,
                  color: AppColors.transferFailed,
                  onTap: () => controller.cancel(transfer.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final completed = batch.where((t) => t.state == TransferState.completed);
    final failed = batch.where((t) => t.state == TransferState.failed);
    final cancelled = batch.where((t) => t.state == TransferState.cancelled);
    final totalBytes = completed.fold<int>(0, (s, t) => s + t.bytesTransferred);
    final allOk = failed.isEmpty && cancelled.isEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: allOk ? AppColors.transferComplete.withValues(alpha: 0.1) : AppColors.transferFailed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                allOk ? LucideIcons.check : LucideIcons.x,
                size: 64,
                color: allOk ? AppColors.transferComplete : AppColors.transferFailed,
              ),
            ),
            const Gap(32),
            Text(
              allOk ? 'Transfer Complete' : 'Transfer Finished',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const Gap(16),
            if (completed.isNotEmpty)
              Text(
                '${completed.length} file(s) successfully sent (${_formatBytes(totalBytes)})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            if (failed.isNotEmpty || cancelled.isNotEmpty) ...[
              const Gap(8),
              Text(
                '${failed.length + cancelled.length} file(s) failed or cancelled.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: AppColors.transferFailed,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const Gap(16),
            Text(
              'Time Elapsed: ${_formatDuration(elapsed)}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Gap(48),
            FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                'Done',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
