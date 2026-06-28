import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/device_provider.dart';

class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(LucideIcons.arrowLeft, color: colorScheme.onSurface),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _scannerController.toggleTorch(),
                    icon: Icon(LucideIcons.zap, color: colorScheme.onSurfaceVariant),
                    tooltip: 'Toggle flash',
                  ),
                  IconButton(
                    onPressed: () => _scannerController.switchCamera(),
                    icon: Icon(LucideIcons.refreshCw, color: colorScheme.onSurfaceVariant),
                    tooltip: 'Switch camera',
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Scan QR',
                    style: GoogleFonts.outfit(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                    ),
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.primary, width: 2),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.scanLine, size: 24, color: colorScheme.primary),
                  ),
                  const Gap(16),
                  Text(
                    'Point your camera at a Sendate QR code to connect instantly.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null || !code.startsWith('sendate://')) return;

    _hasScanned = true;
    _scannerController.stop();

    // Parse: sendate://deviceId/name/fingerprint/[ip]/[port]
    final parts = code.replaceFirst('sendate://', '').split('/');
    if (parts.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid QR code')),
      );
      Navigator.pop(context);
      return;
    }

    final device = DeviceModel(
      id: parts[0],
      name: Uri.decodeComponent(parts[1]),
      deviceType: DeviceType.unknown,
      fingerprint: parts[2],
      trustLevel: TrustLevel.known,
      ipAddress: parts.length > 3 ? parts[3] : null,
      port: parts.length > 4 ? int.tryParse(parts[4]) : null,
      lastSeen: DateTime.now(),
    );

    // Add as nearby device
    ref.read(nearbyDevicesProvider.notifier).addDevice(device);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Found: ${device.name}')),
    );

    if (mounted) Navigator.pop(context);
  }
}
