import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../../../../core/constants/app_constants.dart';

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
                    'Receive',
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
                    onPressed: () => _showQRDialog(context, displayDevice),
                    icon: Icon(LucideIcons.qrCode, color: colorScheme.onSurfaceVariant),
                  ),
                  IconButton(
                    onPressed: () => showHelpGuide(context, title: 'Receive Help', items: receiveGuideItems),
                    icon: Icon(LucideIcons.helpCircle, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const Gap(40),

          // Radar & Status Hero Section
          Center(
            child: Column(
              children: [
                _PulsingRadar(color: colorScheme.primary),
                const Gap(32),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _statusText(receiveMode),
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const Gap(8),
                Text(
                  _statusSubtext(receiveMode),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Gap(24),
                _NetworkStatusChip(),
              ],
            ),
          ),
          const Gap(48),

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
          const Gap(48),

          // Settings Section
          Text(
            'Settings',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const Gap(16),
          Text(
            'Visibility Mode',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(8),
          ReceiveModeSelector(
            mode: receiveMode,
            onChanged: (mode) {
              ref.read(receiveModeProvider.notifier).state = mode;
              ref.read(discoveryServiceProvider).hiddenMode =
                  mode == ReceiveMode.hidden;
            },
          ),
          const Gap(24),
          _BrowserReceiverToggle(),
          const Gap(120), // Extra padding to clear floating nav bar
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

  void _showQRDialog(BuildContext context, DeviceModel device) async {
    final ip = await ref.read(networkServiceProvider).getLocalIp() ?? '';
    if (!context.mounted) return;
    final qrData = 'sendate://${device.id}/${device.name}/${device.fingerprint}/$ip/${AppConstants.transferPort}';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Scan to connect',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: SizedBox(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
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
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _controller,
        child: Center(
          child: Icon(
            LucideIcons.smartphone,
            size: 32,
            color: widget.color,
          ),
        ),
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              color: widget.color,
            ),
            child: child,
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
      final opacity = (1.0 - wave) * 0.4;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.fill,
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

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHotspot ? LucideIcons.wifi : LucideIcons.wifi,
              size: 16,
              color: isDiscovering ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const Gap(8),
            Text(
              ip != null
                  ? '${isHotspot ? "Hotspot" : "WiFi"} • $ip'
                  : 'No network',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDiscovering ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
            if (isDiscovering) ...[
              const Gap(12),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
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
    final ip = await ref.read(networkServiceProvider).getLocalIp();
    final urlBase = 'http://$ip:${service.port}';
    final receiverUrl =
        password != null ? '$urlBase?pwd=$password' : urlBase;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.globe, size: 20, color: colorScheme.onSurface),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Browser Receiver',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Receive files from any web browser',
                    style: GoogleFonts.plusJakartaSans(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
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
        
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          height: !isActive && _usePassword ? 100 : (!isActive ? 40 : 120),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Password setup (when off)
                if (!isActive) ...[
                  const Gap(12),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _usePassword,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              setState(() => _usePassword = v ?? false),
                        ),
                      ),
                      const Gap(8),
                      Text(
                        'Require password',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      ),
                    ],
                  ),
                  if (_usePassword) ...[
                    const Gap(12),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        hintText: 'Enter secure password',
                        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword
                              ? LucideIcons.eyeOff
                              : LucideIcons.eye),
                          iconSize: 18,
                          color: colorScheme.onSurfaceVariant,
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                  ],
                ],

                // Active state details
                if (isActive && url != null) ...[
                  const Gap(16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            url.contains('?pwd=')
                                ? url.split('?pwd=').first
                                : url,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
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
                              size: 18, color: colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                  if (password != null) ...[
                    const Gap(12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.lock,
                                size: 14, color: colorScheme.onSurfaceVariant),
                            const Gap(6),
                            Text(
                              'Password protected',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
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
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
