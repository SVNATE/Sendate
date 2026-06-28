import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      'Folder Sync',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.plus, color: colorScheme.onSurfaceVariant),
                  tooltip: 'Add sync folder',
                  onPressed: () => _showAddDialog(context, ref),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: configsAsync.when(
              loading: () => Center(child: CircularProgressIndicator(color: colorScheme.primary)),
              error: (e, _) => Center(child: Text('Error: $e', style: GoogleFonts.plusJakartaSans(color: colorScheme.error))),
              data: (configs) => configs.isEmpty
                  ? _EmptyState(onAdd: () => _showAddDialog(context, ref))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: configs.length,
                      itemBuilder: (context, i) => _SyncConfigTile(
                        config: configs[i],
                        onRemove: () => ref.read(folderSyncConfigsProvider.notifier).removeConfig(configs[i].id),
                        onSyncNow: () => _syncNow(context, ref, configs[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref, FolderSyncConfig config) async {
    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(SnackBar(content: Text('Syncing ${config.localPath.split('/').last}...')));
    try {
      final result = await ref.read(folderSyncConfigsProvider.notifier).syncNow(config);
      snack.clearSnackBars();
      snack.showSnackBar(
        SnackBar(content: Text('Sync done — ${result.synced} sent, ${result.errors} errors')),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
          Icon(LucideIcons.folderSync, size: 80, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const Gap(24),
          Text(
            'No sync folders',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const Gap(8),
          Text(
            'Tap + to add a folder to sync',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(32),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text('Add Sync Folder', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
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
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.folderSync, size: 20, color: colorScheme.primary),
              ),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.localPath.split('/').last,
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      config.localPath,
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(LucideIcons.moreVertical, color: colorScheme.onSurfaceVariant),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onSelected: (v) {
                  if (v == 'sync') onSyncNow();
                  if (v == 'remove') _confirmRemove(context);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'sync',
                      child: Text('Sync now', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500))),
                  PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500, color: colorScheme.error))),
                ],
              ),
            ],
          ),
          const Gap(16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(LucideIcons.smartphone, config.deviceName),
              _Chip(LucideIcons.arrowRightLeft, _modeName),
              _Chip(LucideIcons.timer, _intervalLabel),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remove Sync?', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800)),
              const Gap(12),
              Text(
                'Are you sure you want to remove the sync task for "${config.localPath.split('/').last}"?',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      onPressed: () => Navigator.pop(ctx),
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
                        Navigator.pop(ctx);
                        onRemove();
                      },
                      child: Text('Remove', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onError)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const Gap(6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AddSyncSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddSyncSheet> createState() => _AddSyncSheetState();
}

class _AddSyncSheetState extends ConsumerState<_AddSyncSheet> {
  String? _selectedPath;
  DeviceModel? _selectedDevice;
  SyncMode _syncMode = SyncMode.oneWay;
  ConflictResolution _conflict = ConflictResolution.keepBoth;
  Duration? _interval; 
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
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Sync Folder', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800)),
              const Gap(24),

              _SectionLabel('Local Folder'),
              const Gap(8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(LucideIcons.folderOpen, size: 18),
                  label: Text(_selectedPath?.split('/').last ?? 'Choose folder…', style: GoogleFonts.plusJakartaSans()),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _pickFolder,
                ),
              ),

              const Gap(20),

              _SectionLabel('Target Device'),
              const Gap(8),
              if (nearbyDevices.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text('No nearby devices found', style: GoogleFonts.plusJakartaSans(color: colorScheme.onSurfaceVariant)),
                  ),
                )
              else
                DropdownButtonFormField<DeviceModel>(
                  value: _selectedDevice,
                  hint: Text('Select device', style: GoogleFonts.plusJakartaSans()),
                  items: nearbyDevices
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.name, style: GoogleFonts.plusJakartaSans())))
                      .toList(),
                  onChanged: (d) => setState(() => _selectedDevice = d),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),

              const Gap(20),

              _SectionLabel('Sync Mode'),
              const Gap(8),
              SegmentedButton<SyncMode>(
                segments: [
                  ButtonSegment(
                      value: SyncMode.oneWay,
                      label: Text('One-way', style: GoogleFonts.plusJakartaSans()),
                      icon: const Icon(LucideIcons.arrowRight, size: 16)),
                  ButtonSegment(
                      value: SyncMode.twoWay,
                      label: Text('Two-way', style: GoogleFonts.plusJakartaSans()),
                      icon: const Icon(LucideIcons.arrowLeftRight, size: 16)),
                  ButtonSegment(
                      value: SyncMode.manual,
                      label: Text('Manual', style: GoogleFonts.plusJakartaSans()),
                      icon: const Icon(LucideIcons.hand, size: 16)),
                ],
                selected: {_syncMode},
                onSelectionChanged: (s) => setState(() => _syncMode = s.first),
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),

              const Gap(20),

              _SectionLabel('Conflict Resolution'),
              const Gap(8),
              DropdownButtonFormField<ConflictResolution>(
                value: _conflict,
                items: [
                  DropdownMenuItem(value: ConflictResolution.keepBoth, child: Text('Keep both', style: GoogleFonts.plusJakartaSans())),
                  DropdownMenuItem(value: ConflictResolution.replace, child: Text('Replace', style: GoogleFonts.plusJakartaSans())),
                  DropdownMenuItem(value: ConflictResolution.skip, child: Text('Skip', style: GoogleFonts.plusJakartaSans())),
                ],
                onChanged: (v) => setState(() => _conflict = v ?? ConflictResolution.keepBoth),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),

              const Gap(20),

              _SectionLabel('Auto-Sync Interval'),
              const Gap(8),
              DropdownButtonFormField<Duration?>(
                value: _interval,
                items: _intervalOptions.entries
                    .map((e) => DropdownMenuItem<Duration?>(
                        value: e.value, child: Text(e.key, style: GoogleFonts.plusJakartaSans())))
                    .toList(),
                onChanged: (v) => setState(() => _interval = v),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),

              const Gap(32),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSave && !_saving ? _save : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                        )
                      : Text('Add Sync Folder', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave => _selectedPath != null && _selectedDevice != null;

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
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}
