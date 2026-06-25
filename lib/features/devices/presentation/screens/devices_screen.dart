import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/utils/platform_capabilities.dart';
import '../../../../core/utils/platform_detector.dart';
import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/device_provider.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/widgets/device_avatar.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider).startAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final trustedDevices = ref.watch(trustedDevicesProvider);
    final nearbyDevices = ref.watch(allNearbyDevicesProvider)
        .where((d) => !trustedDevices.any((t) => t.id == d.id))
        .toList();
    final favoriteIds = ref.watch(favoritedDevicesProvider);
    final pinnedDevices = [...trustedDevices, ...nearbyDevices]
        .where((d) => favoriteIds.contains(d.id))
        .toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Devices'),
            actions: [
              IconButton(
                onPressed: () => showHelpGuide(context, title: 'Devices Help', items: devicesGuideItems),
                icon: Icon(LucideIcons.helpCircle),
                tooltip: 'Help',
              ),
              // Bluetooth scan only on mobile platforms
              if (PlatformCapabilities.hasBluetooth)
                IconButton(
                  onPressed: () =>
                      ref.read(discoveryControllerProvider).startBluetoothScan(),
                  icon: Icon(LucideIcons.bluetooth),
                  tooltip: 'Bluetooth scan',
                ),
              // QR Scan only available on mobile (camera required)
              if (Platform.isAndroid || Platform.isIOS)
                FutureBuilder<bool>(
                  future: PlatformDetector.isTV(),
                  builder: (context, snapshot) {
                    final isTV = snapshot.data ?? false;
                    if (isTV) return const SizedBox.shrink();
                    return IconButton(
                      onPressed: () => context.push('/connect/scan'),
                      icon: Icon(LucideIcons.scanLine),
                      tooltip: 'Scan QR',
                    );
                  },
                ),
              IconButton(
                onPressed: () => context.push('/connect/manual'),
                icon: Icon(LucideIcons.globe),
                tooltip: 'Manual IP',
              ),
              IconButton(
                onPressed: () =>
                    ref.read(discoveryControllerProvider).restartDiscovery(),
                icon: Icon(LucideIcons.refreshCw),
                tooltip: 'Refresh',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                const Gap(8),
                // Pinned Section
                if (pinnedDevices.isNotEmpty) ...
                  [
                    _SectionHeader(
                      title: 'Pinned',
                      count: pinnedDevices.length,
                      icon: LucideIcons.pin,
                    ),
                    const Gap(12),
                    ...pinnedDevices.map(
                      (d) => _DeviceTile(
                        device: d,
                        onTrust: trustedDevices.any((t) => t.id == d.id)
                            ? null
                            : () => _trustDevice(d),
                        onBlock: () => _blockDevice(d),
                        onRemove: trustedDevices.any((t) => t.id == d.id)
                            ? () => _removeTrusted(d)
                            : null,
                      ),
                    ),
                    const Gap(24),
                  ],
                // Trusted Section
                if (trustedDevices.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Trusted',
                    count: trustedDevices.length,
                    icon: LucideIcons.shieldCheck,
                  ),
                  const Gap(12),
                  ...trustedDevices.map(
                    (d) => _DeviceTile(
                      device: d,
                      onTrust: null,
                      onBlock: () => _blockDevice(d),
                      onRemove: () => _removeTrusted(d),
                    ),
                  ),
                  const Gap(24),
                ],
                // Nearby Section
                _SectionHeader(
                  title: 'Nearby',
                  count: nearbyDevices.length,
                  icon: LucideIcons.radar,
                ),
                const Gap(12),
                if (nearbyDevices.isEmpty)
                  _EmptySection(
                    icon: LucideIcons.radar,
                    message: 'No nearby devices found',
                    isLoading: ref.watch(discoveryActiveProvider),
                  )
                else
                  ...nearbyDevices.map(
                    (d) => _DeviceTile(
                      device: d,
                      onTrust: () => _trustDevice(d),
                      onBlock: () => _blockDevice(d),
                      onRemove: null,
                    ),
                  ),
                const Gap(32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _trustDevice(DeviceModel device) {
    ref.read(trustedDevicesProvider.notifier).addDevice(device);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${device.name} trusted'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(trustedDevicesProvider.notifier).removeDevice(device.id),
        ),
      ),
    );
  }

  void _blockDevice(DeviceModel device) {
    ref.read(trustedDevicesProvider.notifier).removeDevice(device.id);
    ref.read(blockedDevicesProvider.notifier).block(device.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${device.name} blocked'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(blockedDevicesProvider.notifier).unblock(device.id),
        ),
      ),
    );
  }

  void _removeTrusted(DeviceModel device) {
    ref.read(trustedDevicesProvider.notifier).removeDevice(device.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${device.name} removed from trusted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const Gap(8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Gap(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final DeviceModel device;
  final VoidCallback? onTrust;
  final VoidCallback? onBlock;
  final VoidCallback? onRemove;

  const _DeviceTile({
    required this.device,
    this.onTrust,
    this.onBlock,
    this.onRemove,
  });

  String _connectionLabel(DeviceModel device) {
    if (device.connectionType == ConnectionType.bluetooth) return 'Bluetooth';
    if (device.connectionType == ConnectionType.manual) return 'Manual';
    return device.ipAddress ?? 'WiFi';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFav = ref.watch(favoritedDevicesProvider).contains(device.id);

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
          '${device.deviceType.name} • ${_connectionLabel(device)}',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(LucideIcons.moreVertical,
              color: colorScheme.onSurfaceVariant),
          onSelected: (value) {
            switch (value) {
              case 'message':
                context.push('/chat', extra: device);
              case 'pin':
                ref
                    .read(favoritedDevicesProvider.notifier)
                    .toggleFavorite(device.id);
              case 'trust':
                onTrust?.call();
              case 'block':
                onBlock?.call();
              case 'remove':
                onRemove?.call();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'message', child: Text('Message')),
            PopupMenuItem(
              value: 'pin',
              child: Text(isFav ? 'Unpin' : 'Pin'),
            ),
            if (onTrust != null)
              const PopupMenuItem(value: 'trust', child: Text('Trust')),
            if (onBlock != null)
              const PopupMenuItem(value: 'block', child: Text('Block')),
            if (onRemove != null)
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isLoading;

  const _EmptySection({
    required this.icon,
    required this.message,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          if (isLoading)
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            )
          else
            Icon(
              icon,
              size: 36,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          const Gap(12),
          Text(
            isLoading ? 'Scanning...' : message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
