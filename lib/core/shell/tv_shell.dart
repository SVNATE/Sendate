import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/models/device_model.dart';
import '../../shared/providers/device_provider.dart';
import '../../shared/providers/discovery_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/transfer_provider.dart';

/// Android TV optimized layout with large cards, focus-based navigation,
/// and QR pairing as primary connection method.
class TvShell extends ConsumerStatefulWidget {
  const TvShell({super.key});

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(currentDeviceProvider);
    final deviceName = ref.watch(deviceNameProvider);
    final nearbyDevices = ref.watch(allNearbyDevicesProvider);
    final history = ref.watch(transferHistoryProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final displayDevice = device?.copyWith(name: deviceName);
    final qrData = displayDevice != null
        ? 'sendate://${displayDevice.id}/${displayDevice.name}/${displayDevice.fingerprint}'
        : '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Row(
            children: [
              // Left panel — QR + Device Info
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Sendate',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Gap(8),
                    Text(
                      displayDevice?.name ?? 'TV',
                      style: TextStyle(fontSize: 18, color: colorScheme.onSurfaceVariant),
                    ),
                    const Gap(32),
                    // QR Code for pairing
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                    const Gap(16),
                    Text(
                      'Scan to connect',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Gap(48),
              // Right panel — Connected Devices + Recent Transfers
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected Devices',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Gap(16),
                    if (nearbyDevices.isEmpty)
                      _TvEmptyCard(
                        icon: LucideIcons.radar,
                        message: 'Waiting for devices...',
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: nearbyDevices.length,
                          itemBuilder: (context, index) => _TvDeviceCard(
                            device: nearbyDevices[index],
                          ),
                        ),
                      ),
                    const Gap(24),
                    Text(
                      'Recent Transfers',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Gap(16),
                    if (history.isEmpty)
                      _TvEmptyCard(
                        icon: LucideIcons.clock,
                        message: 'No transfers yet',
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: history.take(5).length,
                          itemBuilder: (context, index) => _TvTransferCard(
                            transfer: history[index],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvDeviceCard extends StatelessWidget {
  final DeviceModel device;
  const _TvDeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(LucideIcons.smartphone, size: 32, color: colorScheme.primary),
            const Gap(16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  Text(device.ipAddress ?? '', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(LucideIcons.wifi, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _TvTransferCard extends StatelessWidget {
  final dynamic transfer;
  const _TvTransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(LucideIcons.fileCheck, size: 24, color: const Color(0xFF22C55E)),
            const Gap(12),
            Expanded(
              child: Text(transfer.fileName as String, style: const TextStyle(fontSize: 16)),
            ),
            Text(transfer.deviceName as String, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _TvEmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _TvEmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Row(
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const Gap(16),
          Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
