import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/browser_receiver_provider.dart';
import '../../../../shared/providers/device_provider.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';
import '../widgets/receive_mode_selector.dart';
import '../widgets/device_card_widget.dart';

enum ReceiveMode { public, trustedOnly, hidden }

final receiveModeProvider =
    StateProvider<ReceiveMode>((ref) => ReceiveMode.public);

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentDevice = ref.watch(currentDeviceProvider);
    final receiveMode = ref.watch(receiveModeProvider);
    final deviceName = ref.watch(deviceNameProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Use updated device name from settings
    final displayDevice = currentDevice?.copyWith(name: deviceName) ??
        DeviceModel(
          id: 'self',
          name: deviceName,
          deviceType: DeviceType.phone,
          fingerprint: '••••••',
        );

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Receive'),
            actions: [
              IconButton(
                onPressed: () => showHelpGuide(context, title: 'Receive Help', items: receiveGuideItems),
                icon: Icon(LucideIcons.helpCircle),
                tooltip: 'Help',
              ),
              IconButton(
                onPressed: () => _showQRDialog(context, displayDevice),
                icon: Icon(LucideIcons.qrCode),
                tooltip: 'Show QR Code',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                const Gap(8),
                // Device Card
                DeviceCardWidget(
                  device: displayDevice,
                  onCopyAddress: () {
                    Clipboard.setData(ClipboardData(
                      text: displayDevice.fingerprint,
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Fingerprint copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const Gap(16),
                // Network status
                _NetworkStatusChip(),
                const Gap(24),
                // Receive Mode
                Text(
                  'Receive Mode',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Gap(12),
                ReceiveModeSelector(
                  mode: receiveMode,
                  onChanged: (mode) {
                    ref.read(receiveModeProvider.notifier).state = mode;
                    // Enforce hidden mode on discovery
                    ref.read(discoveryServiceProvider).hiddenMode =
                        mode == ReceiveMode.hidden;
                  },
                ),
                const Gap(24),
                // Browser Receiver toggle
                _BrowserReceiverToggle(),
                const Gap(32),
                // Status indicator
                Center(
                  child: Column(
                    children: [
                      _PulsingRadar(color: colorScheme.primary),
                      const Gap(16),
                      Text(
                        _statusText(receiveMode),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const Gap(4),
                      Text(
                        _statusSubtext(receiveMode),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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

  String _statusText(ReceiveMode mode) => switch (mode) {
        ReceiveMode.public => 'Ready to receive',
        ReceiveMode.trustedOnly => 'Trusted only',
        ReceiveMode.hidden => 'Hidden mode',
      };

  String _statusSubtext(ReceiveMode mode) => switch (mode) {
        ReceiveMode.public => 'Your device is visible to everyone nearby',
        ReceiveMode.trustedOnly =>
          'Only trusted devices can see and send to you',
        ReceiveMode.hidden =>
          'Invisible — share your QR or code to connect',
      };

  void _showQRDialog(BuildContext context, DeviceModel device) {
    final qrData = 'sendate://${device.id}/${device.name}/${device.fingerprint}';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan to connect'),
        content: SizedBox(
          width: 250,
          height: 250,
          child: Center(
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PulsingRadar extends StatefulWidget {
  final Color color;

  const _PulsingRadar({required this.color});

  @override
  State<_PulsingRadar> createState() => _PulsingRadarState();
}

class _PulsingRadarState extends State<_PulsingRadar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              color: widget.color,
            ),
            child: Center(
              child: Icon(
                LucideIcons.radio,
                size: 32,
                color: widget.color,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final wave = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * wave;
      final opacity = (1.0 - wave) * 0.3;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _NetworkStatusChip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDiscovering = ref.watch(discoveryActiveProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<String?>(
      future: ref.read(networkServiceProvider).getLocalIp(),
      builder: (context, snapshot) {
        final ip = snapshot.data;
        final isHotspot = ip != null &&
            (ip.startsWith('192.168.43.') ||
                ip.startsWith('192.168.49.') ||
                ip.startsWith('172.20.10.'));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDiscovering
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isHotspot ? LucideIcons.wifi : LucideIcons.wifi,
                size: 14,
                color: isDiscovering ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
              const Gap(8),
              Text(
                ip != null
                    ? '${isHotspot ? "Hotspot" : "WiFi"} • $ip'
                    : 'No network',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (isDiscovering) ...[
                const Gap(8),
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BrowserReceiverToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(browserReceiverActiveProvider);
    final url = ref.watch(browserReceiverUrlProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.globe, size: 18, color: colorScheme.primary),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Browser Receiver',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Switch(
                  value: isActive,
                  onChanged: (value) async {
                    final service = ref.read(browserReceiverServiceProvider);
                    if (value) {
                      await service.start();
                      final ip = await ref.read(networkServiceProvider).getLocalIp();
                      final receiverUrl = 'http://$ip:${service.port}';
                      ref.read(browserReceiverActiveProvider.notifier).state = true;
                      ref.read(browserReceiverUrlProvider.notifier).state = receiverUrl;
                    } else {
                      await service.stop();
                      ref.read(browserReceiverActiveProvider.notifier).state = false;
                      ref.read(browserReceiverUrlProvider.notifier).state = null;
                    }
                  },
                ),
              ],
            ),
            if (isActive && url != null) ...[
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        url,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: colorScheme.primary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copied'), duration: Duration(seconds: 1)),
                        );
                      },
                      child: Icon(LucideIcons.copy, size: 16, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
              const Gap(4),
              Text(
                'Open this URL in any browser to send files',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
