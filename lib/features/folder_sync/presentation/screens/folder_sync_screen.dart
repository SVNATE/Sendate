import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../services/folder_sync/folder_sync_service.dart';
import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/folder_sync_provider.dart';

class FolderSyncScreen extends ConsumerWidget {
  const FolderSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configsAsync = ref.watch(folderSyncConfigsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folder Sync'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Add sync folder',
            onPressed: () => _showAddDialog(context, ref),
          ),
        ],
      ),
      body: configsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (configs) => configs.isEmpty
            ? _EmptyState(onAdd: () => _showAddDialog(context, ref))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: configs.length,
                itemBuilder: (context, i) => _SyncConfigTile(
                  config: configs[i],
                  onRemove: () => ref
                      .read(folderSyncConfigsProvider.notifier)
                      .removeConfig(configs[i].id),
                  onSyncNow: () => _syncNow(context, ref, configs[i]),
                ),
              ),
      ),
    );
  }

  Future<void> _syncNow(
    BuildContext context,
    WidgetRef ref,
    FolderSyncConfig config,
  ) async {
    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(
      SnackBar(content: Text('Syncing ${config.localPath}...')),
    );
    try {
      final result = await ref
          .read(folderSyncConfigsProvider.notifier)
          .syncNow(config);
      snack.clearSnackBars();
      snack.showSnackBar(
        SnackBar(
          content: Text(
            'Sync done — ${result.synced} sent, ${result.errors} errors',
          ),
        ),
      );
    } catch (e) {
      snack.clearSnackBars();
      snack.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddSyncSheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.folderSync,
              size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const Gap(16),
          Text(
            'No sync folders',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Gap(8),
          Text(
            'Tap + to add a folder to sync with a device',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
          ),
          const Gap(24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(LucideIcons.plus),
            label: const Text('Add Sync Folder'),
          ),
        ],
      ),
    );
  }
}

class _SyncConfigTile extends StatelessWidget {
  final FolderSyncConfig config;
  final VoidCallback onRemove;
  final VoidCallback onSyncNow;

  const _SyncConfigTile({
    required this.config,
    required this.onRemove,
    required this.onSyncNow,
  });

  String get _modeName => switch (config.mode) {
        SyncMode.oneWay => 'One-way',
        SyncMode.twoWay => 'Two-way',
        SyncMode.manual => 'Manual',
      };

  String get _intervalLabel {
    if (config.interval == null) return 'Manual only';
    if (config.interval!.inMinutes < 60) return 'Every ${config.interval!.inMinutes}m';
    return 'Every ${config.interval!.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.folderSync, size: 18, color: colorScheme.primary),
                const Gap(8),
                Expanded(
                  child: Text(
                    config.localPath.split('/').last,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'sync') onSyncNow();
                    if (v == 'remove') _confirmRemove(context);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'sync',
                        child: Text('Sync now')),
                    const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove')),
                  ],
                ),
              ],
            ),
            const Gap(4),
            Text(
              config.localPath,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            const Gap(8),
            Wrap(
              spacing: 8,
              children: [
                _Chip(LucideIcons.smartphone, config.deviceName),
                _Chip(LucideIcons.arrowRightLeft, _modeName),
                _Chip(LucideIcons.timer, _intervalLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Sync?'),
        content: Text('Remove sync for "${config.localPath.split('/').last}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRemove();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.primary),
          const Gap(4),
          Text(
            label,
            style:
                TextStyle(fontSize: 11, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

// ── Add Sync Sheet ────────────────────────────────────────────────────────────

class _AddSyncSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddSyncSheet> createState() => _AddSyncSheetState();
}

class _AddSyncSheetState extends ConsumerState<_AddSyncSheet> {
  String? _selectedPath;
  DeviceModel? _selectedDevice;
  SyncMode _syncMode = SyncMode.oneWay;
  ConflictResolution _conflict = ConflictResolution.keepBoth;
  Duration? _interval; // null = manual
  bool _saving = false;

  final _intervalOptions = <String, Duration?>{
    'Manual only': null,
    'Every 5 min': const Duration(minutes: 5),
    'Every 30 min': const Duration(minutes: 30),
    'Every hour': const Duration(hours: 1),
    'Every 6 hours': const Duration(hours: 6),
  };

  @override
  Widget build(BuildContext context) {
    final nearbyDevices = ref.watch(allNearbyDevicesProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Sync Folder',
              style: Theme.of(context).textTheme.titleLarge),
          const Gap(20),

          // Folder picker
          _SectionLabel('Local Folder'),
          const Gap(8),
          OutlinedButton.icon(
            icon: const Icon(LucideIcons.folderOpen),
            label: Text(_selectedPath?.split('/').last ?? 'Choose folder…'),
            onPressed: _pickFolder,
          ),

          const Gap(16),

          // Device picker
          _SectionLabel('Target Device'),
          const Gap(8),
          if (nearbyDevices.isEmpty)
            const Text('No nearby devices',
                style: TextStyle(fontSize: 13, color: Colors.grey))
          else
            DropdownButtonFormField<DeviceModel>(
              value: _selectedDevice,
              hint: const Text('Select device'),
              items: nearbyDevices
                  .map((d) => DropdownMenuItem(
                      value: d, child: Text(d.name)))
                  .toList(),
              onChanged: (d) => setState(() => _selectedDevice = d),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

          const Gap(16),

          // Sync mode
          _SectionLabel('Sync Mode'),
          const Gap(8),
          SegmentedButton<SyncMode>(
            segments: [
              ButtonSegment(
                  value: SyncMode.oneWay,
                  label: const Text('One-way'),
                  icon: const Icon(LucideIcons.arrowRight)),
              ButtonSegment(
                  value: SyncMode.twoWay,
                  label: const Text('Two-way'),
                  icon: const Icon(LucideIcons.arrowLeftRight)),
              ButtonSegment(
                  value: SyncMode.manual,
                  label: const Text('Manual'),
                  icon: const Icon(LucideIcons.hand)),
            ],
            selected: {_syncMode},
            onSelectionChanged: (s) =>
                setState(() => _syncMode = s.first),
          ),

          const Gap(16),

          // Conflict resolution
          _SectionLabel('Conflict Resolution'),
          const Gap(8),
          DropdownButtonFormField<ConflictResolution>(
            value: _conflict,
            items: const [
              DropdownMenuItem(
                  value: ConflictResolution.keepBoth,
                  child: Text('Keep both')),
              DropdownMenuItem(
                  value: ConflictResolution.replace,
                  child: Text('Replace')),
              DropdownMenuItem(
                  value: ConflictResolution.skip,
                  child: Text('Skip')),
            ],
            onChanged: (v) =>
                setState(() => _conflict = v ?? ConflictResolution.keepBoth),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const Gap(16),

          // Interval
          _SectionLabel('Auto-Sync Interval'),
          const Gap(8),
          DropdownButtonFormField<Duration?>(
            value: _interval,
            items: _intervalOptions.entries
                .map((e) => DropdownMenuItem<Duration?>(
                    value: e.value, child: Text(e.key)))
                .toList(),
            onChanged: (v) => setState(() => _interval = v),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const Gap(24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _canSave && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add Sync Folder'),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canSave =>
      _selectedPath != null && _selectedDevice != null;

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) setState(() => _selectedPath = path);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final config = FolderSyncConfig(
      id: const Uuid().v4(),
      localPath: _selectedPath!,
      deviceId: _selectedDevice!.id,
      deviceName: _selectedDevice!.name,
      mode: _syncMode,
      conflictResolution: _conflict,
      interval: _interval,
    );
    await ref.read(folderSyncConfigsProvider.notifier).addConfig(config);
    if (mounted) Navigator.pop(context);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      );
}
