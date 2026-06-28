import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
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
                    'Devices',
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => ref.read(discoveryControllerProvider).restartDiscovery(),
                    icon: Icon(LucideIcons.refreshCw, color: colorScheme.onSurfaceVariant),
                    tooltip: 'Refresh',
                  ),
                  if (Platform.isAndroid || Platform.isIOS)
                    FutureBuilder<bool>(
                      future: PlatformDetector.isTV(),
                      builder: (context, snapshot) {
                        final isTV = snapshot.data ?? false;
                        if (isTV) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: () => context.push('/connect/scan'),
                          icon: Icon(LucideIcons.scanLine, color: colorScheme.onSurfaceVariant),
                          tooltip: 'Scan QR',
                        );
                      },
                    ),
                  PopupMenuButton<String>(
                    icon: Icon(LucideIcons.moreVertical, color: colorScheme.onSurfaceVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onSelected: (value) {
                      switch (value) {
                        case 'help':
                          showHelpGuide(context, title: 'Devices Help', items: devicesGuideItems);
                        case 'bluetooth':
                          ref.read(discoveryControllerProvider).startBluetoothScan();
                        case 'manual':
                          context.push('/connect/manual');
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      if (PlatformCapabilities.hasBluetooth)
                        PopupMenuItem<String>(
                          value: 'bluetooth',
                          child: Row(
                            children: [
                              Icon(LucideIcons.bluetooth, size: 20, color: colorScheme.onSurface),
                              const Gap(12),
                              const Text('Bluetooth Scan'),
                            ],
                          ),
                        ),
                      PopupMenuItem<String>(
                        value: 'manual',
                        child: Row(
                          children: [
                            Icon(LucideIcons.globe, size: 20, color: colorScheme.onSurface),
                            const Gap(12),
                            const Text('Manual IP'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'help',
                        child: Row(
                          children: [
                            Icon(LucideIcons.helpCircle, size: 20, color: colorScheme.onSurface),
                            const Gap(12),
                            const Text('Help'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const Gap(40),

          // Pinned Section
          if (pinnedDevices.isNotEmpty) ...[
            _SectionHeader(
              title: 'Pinned',
              count: pinnedDevices.length,
              icon: LucideIcons.pin,
            ),
            const Gap(16),
            ...pinnedDevices.map(
              (d) => _DeviceTile(
                device: d,
                onTrust: trustedDevices.any((t) => t.id == d.id) ? null : () => _trustDevice(d),
                onBlock: () => _blockDevice(d),
                onRemove: trustedDevices.any((t) => t.id == d.id) ? () => _removeTrusted(d) : null,
              ),
            ),
            const Gap(32),
          ],

          // Trusted Section
          if (trustedDevices.isNotEmpty) ...[
            _SectionHeader(
              title: 'Trusted',
              count: trustedDevices.length,
              icon: LucideIcons.shieldCheck,
            ),
            const Gap(16),
            ...trustedDevices.map(
              (d) => _DeviceTile(
                device: d,
                onTrust: null,
                onBlock: () => _blockDevice(d),
                onRemove: () => _removeTrusted(d),
              ),
            ),
            const Gap(32),
          ],

          // Nearby Section
          _SectionHeader(
            title: 'Nearby',
            count: nearbyDevices.length,
            icon: LucideIcons.radar,
          ),
          const Gap(16),
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
          const Gap(120), // Extra padding to clear floating nav bar
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
          onPressed: () => ref.read(trustedDevicesProvider.notifier).removeDevice(device.id),
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
          onPressed: () => ref.read(blockedDevicesProvider.notifier).unblock(device.id),
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
        Icon(icon, size: 24, color: colorScheme.primary),
        const Gap(12),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
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

  void _showActionSheet(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFav = ref.read(favoritedDevicesProvider).contains(device.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      DeviceAvatar(device: device, size: 48, showTrustBadge: true),
                      const Gap(16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                device.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${device.deviceType.name} • ${_connectionLabel(device)}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(24),
                _ActionTile(
                  icon: LucideIcons.messageSquare,
                  label: 'Message',
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/chat', extra: device);
                  },
                ),
                _ActionTile(
                  icon: isFav ? LucideIcons.pinOff : LucideIcons.pin,
                  label: isFav ? 'Unpin' : 'Pin',
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(favoritedDevicesProvider.notifier).toggleFavorite(device.id);
                  },
                ),
                if (onTrust != null)
                  _ActionTile(
                    icon: LucideIcons.shieldCheck,
                    label: 'Trust',
                    onTap: () {
                      Navigator.pop(context);
                      onTrust?.call();
                    },
                  ),
                if (onRemove != null)
                  _ActionTile(
                    icon: LucideIcons.userMinus,
                    label: 'Remove Trust',
                    onTap: () {
                      Navigator.pop(context);
                      onRemove?.call();
                    },
                  ),
                if (onBlock != null)
                  _ActionTile(
                    icon: LucideIcons.ban,
                    label: 'Block',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      onBlock?.call();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
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
            '${device.deviceType.name} • ${_connectionLabel(device)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Icon(LucideIcons.moreVertical, color: colorScheme.onSurfaceVariant),
          onTap: () => _showActionSheet(context, ref),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : colorScheme.onSurface;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
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
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          if (isLoading)
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
              icon,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          const Gap(24),
          Text(
            isLoading ? 'Scanning...' : message,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
