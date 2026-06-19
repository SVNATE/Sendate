import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/device_provider.dart';

class ManualConnectScreen extends ConsumerStatefulWidget {
  const ManualConnectScreen({super.key});

  @override
  ConsumerState<ManualConnectScreen> createState() =>
      _ManualConnectScreenState();
}

class _ManualConnectScreenState extends ConsumerState<ManualConnectScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '53318');
  bool _isConnecting = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Connect')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter device IP address',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Gap(8),
            Text(
              'Connect to a device by entering its IP address directly. '
              'Use this when automatic discovery doesn\'t find the device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const Gap(24),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.100',
                prefixIcon: Icon(LucideIcons.globe),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const Gap(16),
            TextField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: 'Port',
                hintText: '53318',
                prefixIcon: Icon(LucideIcons.hash),
              ),
              keyboardType: TextInputType.number,
            ),
            const Gap(32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isConnecting ? null : _connect,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(LucideIcons.link),
                label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _connect() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 53318;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }

    // Validate IP format
    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid IP address format')),
      );
      return;
    }

    setState(() => _isConnecting = true);

    // Create a manual device entry
    final device = DeviceModel(
      id: 'manual-$ip:$port',
      name: ip,
      deviceType: DeviceType.unknown,
      fingerprint: '',
      ipAddress: ip,
      port: port,
      connectionType: ConnectionType.manual,
      trustLevel: TrustLevel.unknown,
      lastSeen: DateTime.now(),
    );

    // Add to nearby devices
    ref.read(nearbyDevicesProvider.notifier).addDevice(device);

    setState(() => _isConnecting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Device added: $ip:$port')),
    );

    Navigator.pop(context);
  }
}
