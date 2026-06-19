import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/transfer_service_provider.dart';
import '../../../../shared/widgets/device_avatar.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';
import '../widgets/clipboard_send_dialog.dart';

/// Selected files to send
final selectedFilesProvider =
    StateProvider<List<PlatformFile>>((ref) => []);

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  @override
  void initState() {
    super.initState();
    // Start all discovery methods when Send screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider).startAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nearbyDevices = ref.watch(allNearbyDevicesProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Send'),
            actions: [
              IconButton(
                onPressed: () => showHelpGuide(context, title: 'Send Help', items: sendGuideItems),
                icon: Icon(LucideIcons.helpCircle),
                tooltip: 'Help',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                const Gap(8),
                // Content type selector
                _ContentTypeGrid(
                  onPickPhotos: () => _pickFiles(FileType.image),
                  onPickVideos: () => _pickFiles(FileType.video),
                  onPickFiles: () => _pickFiles(FileType.any),
                  onPickFolder: _pickFolder,
                  onClipboard: _sendClipboard,
                ),
                // Selected files preview
                if (selectedFiles.isNotEmpty) ...[
                  const Gap(16),
                  _SelectedFilesPreview(
                    files: selectedFiles,
                    onClear: () => ref
                        .read(selectedFilesProvider.notifier)
                        .state = [],
                  ),
                ],
                const Gap(28),
                // Nearby devices
                Row(
                  children: [
                    Text(
                      'Nearby Devices',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (nearbyDevices.isNotEmpty) ...[
                      const Gap(8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${nearbyDevices.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(discoveryControllerProvider).restartDiscovery(),
                      icon: Icon(LucideIcons.refreshCw, size: 14),
                      label: const Text('Scan'),
                    ),
                  ],
                ),
                const Gap(12),
                if (nearbyDevices.isEmpty)
                  _EmptyDevicesState(
                    isDiscovering: ref.watch(discoveryActiveProvider),
                  )
                else
                  ...nearbyDevices.map(
                    (device) => _NearbyDeviceTile(
                      device: device,
                      hasFiles: selectedFiles.isNotEmpty,
                      onTap: () => _sendToDevice(device),
                    ),
                  ),
                const Gap(24),
              ],
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
      builder: (context) => const ClipboardSendDialog(),
    );
  }

  void _sendToDevice(DeviceModel device) {
    final files = ref.read(selectedFilesProvider);
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select files first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final fileNames = files.map((f) => f.name).join(', ');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send to ${device.name}'),
        content: Text(
          'Send ${files.length} file(s) to ${device.name}?\n\n$fileNames',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _executeSend(device, files);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _executeSend(DeviceModel device, List<PlatformFile> files) {
    final controller = ref.read(transferControllerProvider);
    final filePaths = files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (filePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid file paths')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending ${filePaths.length} file(s) to ${device.name}...'),
        duration: const Duration(seconds: 2),
      ),
    );

    // Clear selection
    ref.read(selectedFilesProvider.notifier).state = [];

    // Send all files
    controller.sendFiles(filePaths: filePaths, target: device);
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
    final aspectRatio = width > 600 ? 1.8 : 1.3;

    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: aspectRatio,
      children: items
          .map(
            (item) => InkWell(
              onTap: item.$3,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$1, size: 24, color: colorScheme.primary),
                    const Gap(8),
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
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

  const _SelectedFilesPreview({
    required this.files,
    required this.onClear,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.paperclip, size: 18, color: colorScheme.primary),
          const Gap(8),
          Expanded(
            child: Text(
              '${files.length} file(s) • ${_formatSize(totalSize)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: Icon(LucideIcons.x, size: 18, color: colorScheme.primary),
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
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            )
          else
            Icon(
              LucideIcons.radar,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          const Gap(16),
          Text(
            isDiscovering ? 'Scanning for devices...' : 'No devices found',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          const Gap(4),
          Text(
            'Make sure both devices are on the same network',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: DeviceAvatar(device: device, showTrustBadge: true),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${device.deviceType.name} • ${device.ipAddress ?? ""}',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: hasFiles
            ? FilledButton.icon(
                onPressed: onTap,
                icon: Icon(LucideIcons.send, size: 16),
                label: const Text('Send'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              )
            : Icon(
                LucideIcons.send,
                color: colorScheme.primary,
                size: 20,
              ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
      ),
    );
  }
}
