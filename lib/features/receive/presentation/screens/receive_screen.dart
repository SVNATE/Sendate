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

class _BrowserReceiverToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BrowserReceiverToggle> createState() =>
      _BrowserReceiverToggleState();
}

class _BrowserReceiverToggleState
    extends ConsumerState<_BrowserReceiverToggle> {
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _usePassword = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final service = ref.read(browserReceiverServiceProvider);
    final password =
        (_usePassword && _passwordController.text.isNotEmpty)
            ? _passwordController.text.trim()
            : null;
    await service.start(password: password);
    if (!service.isRunning) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failed to start browser receiver — port may be in use'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final ip =
        await ref.read(networkServiceProvider).getLocalIp();
    final urlBase = 'http://\$ip:\${service.port}';
    final receiverUrl =
        password != null ? '\$urlBase?pwd=\$password' : urlBase;
    ref.read(browserReceiverActiveProvider.notifier).state = true;
    ref.read(browserReceiverUrlProvider.notifier).state = receiverUrl;
    ref.read(browserReceiverPasswordProvider.notifier).state = password;
  }

  Future<void> _stop() async {
    await ref.read(browserReceiverServiceProvider).stop();
    ref.read(browserReceiverActiveProvider.notifier).state = false;
    ref.read(browserReceiverUrlProvider.notifier).state = null;
    ref.read(browserReceiverPasswordProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(browserReceiverActiveProvider);
    final url = ref.watch(browserReceiverUrlProvider);
    final password = ref.watch(browserReceiverPasswordProvider);
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
                const Expanded(
                  child: Text(
                    'Browser Receiver',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Switch(
                  value: isActive,
                  onChanged: (value) async {
                    if (value) {
                      await _start();
                    } else {
                      await _stop();
                    }
                  },
                ),
              ],
            ),
            // Password toggle (only when not active)
            if (!isActive) ...[
              const Gap(8),
              Row(
                children: [
                  Checkbox(
                    value: _usePassword,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) =>
                        setState(() => _usePassword = v ?? false),
                  ),
                  const Text('Require password',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
              if (_usePassword) ...[
                const Gap(4),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    hintText: 'Enter password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? LucideIcons.eyeOff
                          : LucideIcons.eye),
                      iconSize: 16,
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
              ],
            ],
            if (isActive && url != null) ...[
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        // Show URL without embedded password
                        url.contains('?pwd=')
                            ? url.split('?pwd=').first
                            : url,
                        style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: colorScheme.primary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('URL copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      child: Icon(LucideIcons.copy,
                          size: 16, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
              if (password != null) ...[
                const Gap(6),
                Row(
                  children: [
                    Icon(LucideIcons.lock,
                        size: 12,
                        color: colorScheme.onSurfaceVariant),
                    const Gap(4),
                    Text(
                      'Password protected',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant),
                    ),
                    const Gap(8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Password copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      child: Text(
                        'Copy password',
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ],
              const Gap(4),
              Text(
                'Open this URL in any browser on the same network',
                style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
