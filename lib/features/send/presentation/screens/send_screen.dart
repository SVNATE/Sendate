import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/send_screen_providers.dart';
import '../../../../shared/providers/transfer_service_provider.dart';
import '../../../../shared/widgets/device_avatar.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';
import '../widgets/clipboard_send_dialog.dart';
import '../widgets/save_selection_dialog.dart';
import '../widgets/saved_selections_sheet.dart';
import 'transfer_progress_screen.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider).startAll();
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final nearbyDevices = ref.watch(allNearbyDevicesProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final broadcastMode = ref.watch(broadcastModeProvider);
    final selectedDeviceIds = ref.watch(selectedDeviceIdsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Send',
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
                    children: [
                      IconButton(
                        onPressed: () => _showSavedSelections(context),
                        icon: Icon(LucideIcons.bookmark, color: colorScheme.onSurfaceVariant),
                        tooltip: 'Saved Selections',
                      ),
                      IconButton(
                        onPressed: () {
                          ref.read(broadcastModeProvider.notifier).state = !broadcastMode;
                          ref.read(selectedDeviceIdsProvider.notifier).state = {};
                        },
                        icon: Icon(
                          LucideIcons.radio,
                          color: broadcastMode ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        tooltip: broadcastMode ? 'Exit broadcast mode' : 'Broadcast to multiple devices',
                      ),
                      IconButton(
                        onPressed: () => showHelpGuide(context, title: 'Send Help', items: sendGuideItems),
                        icon: Icon(LucideIcons.helpCircle, color: colorScheme.onSurfaceVariant),
                        tooltip: 'Help',
                      ),
                    ],
                  ),
                ],
              ),
              const Gap(32),

              // Content type selector
              Text(
                'Select payload',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const Gap(16),
              _ContentTypeGrid(
                onPickPhotos: () => _pickFiles(FileType.image),
                onPickVideos: () => _pickFiles(FileType.video),
                onPickFiles: () => _pickFiles(FileType.any),
                onPickFolder: _pickFolder,
                onClipboard: _sendClipboard,
              ),

              // Selected files preview
              if (selectedFiles.isNotEmpty) ...[
                const Gap(24),
                _SelectedFilesPreview(
                  files: selectedFiles,
                  onClear: () => ref.read(selectedFilesProvider.notifier).state = [],
                  onSave: () => _saveSelection(context, selectedFiles),
                ),
              ],
              
              const Gap(48),

              // Nearby devices
              Row(
                children: [
                  Text(
                    'Nearby Devices',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (nearbyDevices.isNotEmpty) ...[
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${nearbyDevices.length}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    onPressed: () => ref.read(discoveryControllerProvider).restartDiscovery(),
                    icon: Icon(LucideIcons.refreshCw, size: 20, color: colorScheme.primary),
                    tooltip: 'Scan again',
                  ),
                ],
              ),
              const Gap(16),

              if (nearbyDevices.isEmpty)
                _EmptyDevicesState(isDiscovering: ref.watch(discoveryActiveProvider))
              else
                ...nearbyDevices.map(
                  (device) => broadcastMode
                      ? _BroadcastDeviceTile(
                          device: device,
                          isSelected: selectedDeviceIds.contains(device.id),
                          onToggle: () {
                            final ids = Set<String>.from(ref.read(selectedDeviceIdsProvider));
                            if (ids.contains(device.id)) {
                              ids.remove(device.id);
                            } else {
                              ids.add(device.id);
                            }
                            ref.read(selectedDeviceIdsProvider.notifier).state = ids;
                          },
                        )
                      : _NearbyDeviceTile(
                          device: device,
                          hasFiles: selectedFiles.isNotEmpty,
                          onTap: () => _sendToDevice(device),
                        ),
                ),
              Gap(broadcastMode ? 180 : 120), // Extra padding to clear floating nav bar
            ],
          ),

          // Broadcast send button (floating at bottom)
          if (broadcastMode && selectedDeviceIds.isNotEmpty && selectedFiles.isNotEmpty)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: SafeArea(
                child: FilledButton.icon(
                  onPressed: () => _broadcastSend(nearbyDevices, selectedDeviceIds, selectedFiles),
                  icon: const Icon(LucideIcons.radio, size: 20),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Broadcast to ${selectedDeviceIds.length} device${selectedDeviceIds.length == 1 ? '' : 's'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickFiles(FileType type) async {
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      ref.read(selectedFilesProvider.notifier).state = result.files;
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Folder selected: $result')),
      );
    }
  }

  void _sendClipboard() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const ClipboardSendDialog(),
    );
  }

  Future<void> _saveSelection(BuildContext context, List<PlatformFile> files) async {
    final paths = files.where((f) => f.path != null).map((f) => f.path!).toList();
    if (paths.isEmpty) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => SaveSelectionDialog(filePaths: paths),
    );
  }

  void _showSavedSelections(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SavedSelectionsSheet(),
    );
  }

  void _sendToDevice(DeviceModel device) {
    final files = ref.read(selectedFilesProvider);
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select files first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final totalSize = files.fold<int>(0, (s, f) => s + f.size);
    final sizeStr = _formatSize(totalSize);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 104),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ready to send?',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(8),
              Text(
                'Sending ${files.length} file(s) ($sizeStr) to ${device.name}.',
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _executeSend(device, files);
                      },
                      child: Text('Send Now', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
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

  void _executeSend(DeviceModel device, List<PlatformFile> files) {
    final controller = ref.read(transferControllerProvider);
    final filePaths = files.where((f) => f.path != null).map((f) => f.path!).toList();

    if (filePaths.isEmpty) return;

    ref.read(selectedFilesProvider.notifier).state = [];
    controller.sendFiles(filePaths: filePaths, target: device);

    context.push(
      '/transfer-progress',
      extra: TransferProgressArgs(
        deviceIds: [device.id],
        deviceName: device.name,
      ),
    );
  }

  void _broadcastSend(List<DeviceModel> allDevices, Set<String> selectedIds, List<PlatformFile> files) {
    final targets = allDevices.where((d) => selectedIds.contains(d.id)).toList();
    if (targets.isEmpty) return;

    final filePaths = files.where((f) => f.path != null).map((f) => f.path!).toList();
    if (filePaths.isEmpty) return;

    final controller = ref.read(transferControllerProvider);
    final deviceIds = targets.map((t) => t.id).toList();

    for (final target in targets) {
      controller.sendFiles(filePaths: filePaths, target: target);
    }

    ref.read(selectedFilesProvider.notifier).state = [];
    ref.read(selectedDeviceIdsProvider.notifier).state = {};
    ref.read(broadcastModeProvider.notifier).state = false;

    context.push(
      '/transfer-progress',
      extra: TransferProgressArgs(
        deviceIds: deviceIds,
        deviceName: targets.length == 1 ? targets.first.name : '${targets.length} devices',
      ),
    );
  }
}

class _ContentTypeGrid extends StatelessWidget {
  final VoidCallback onPickPhotos;
  final VoidCallback onPickVideos;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final VoidCallback onClipboard;

  const _ContentTypeGrid({
    required this.onPickPhotos,
    required this.onPickVideos,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onClipboard,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      (LucideIcons.image, 'Photos', onPickPhotos),
      (LucideIcons.video, 'Videos', onPickVideos),
      (LucideIcons.file, 'Files', onPickFiles),
      (LucideIcons.folder, 'Folders', onPickFolder),
      (LucideIcons.clipboard, 'Clipboard', onClipboard),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 900 ? 5 : width > 600 ? 4 : 3;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: items
          .map(
            (item) => InkWell(
              onTap: item.$3,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$1, size: 28, color: colorScheme.primary),
                    const Gap(12),
                    Text(
                      item.$2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SelectedFilesPreview extends StatelessWidget {
  final List<PlatformFile> files;
  final VoidCallback onClear;
  final VoidCallback onSave;

  const _SelectedFilesPreview({
    required this.files,
    required this.onClear,
    required this.onSave,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalSize = files.fold<int>(0, (sum, f) => sum + (f.size));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.paperclip, size: 20, color: colorScheme.primary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${files.length} file(s) selected',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  _formatSize(totalSize),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Save selection',
            child: IconButton(
              onPressed: onSave,
              icon: Icon(LucideIcons.bookmarkPlus, color: colorScheme.primary),
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: Icon(LucideIcons.x, color: colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _EmptyDevicesState extends StatelessWidget {
  final bool isDiscovering;

  const _EmptyDevicesState({required this.isDiscovering});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          if (isDiscovering)
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          else
            Icon(
              LucideIcons.radar,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          const Gap(24),
          Text(
            isDiscovering ? 'Scanning for devices...' : 'No devices found',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Gap(8),
          Text(
            'Ensure both devices are on the same local network',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  final DeviceModel device;
  final bool hasFiles;
  final VoidCallback onTap;

  const _NearbyDeviceTile({
    required this.device,
    required this.hasFiles,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              DeviceAvatar(device: device, showTrustBadge: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${device.deviceType.name} • ${device.ipAddress ?? ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              hasFiles
                  ? FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: Text('Send', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    )
                  : Icon(
                      LucideIcons.send,
                      color: colorScheme.primary.withValues(alpha: 0.5),
                      size: 20,
                    ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _BroadcastDeviceTile extends StatelessWidget {
  final DeviceModel device;
  final bool isSelected;
  final VoidCallback onToggle;

  const _BroadcastDeviceTile({
    required this.device,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isSelected ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: DeviceAvatar(device: device, showTrustBadge: true),
        title: Text(
          device.name,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          '${device.deviceType.name} • ${device.ipAddress ?? ""}',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (_) => onToggle(),
          activeColor: colorScheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onTap: onToggle,
      ),
      ),
    );
  }
}
