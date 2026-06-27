import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
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
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            onPressed: () => _scannerController.toggleTorch(),
            icon: Icon(LucideIcons.zap),
            tooltip: 'Toggle flash',
          ),
          IconButton(
            onPressed: () => _scannerController.switchCamera(),
            icon: Icon(LucideIcons.refreshCw),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(LucideIcons.scanLine, size: 32, color: colorScheme.primary),
                const Gap(12),
                Text(
                  'Point camera at a Sendate QR code',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
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

    Navigator.pop(context);
  }
}
