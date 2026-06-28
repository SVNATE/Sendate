import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Gap(16),
                    Text(
                      'Manual IP',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Gap(16),
                    Text(
                      'Connect to a device by entering its IP address directly. '
                      'Use this when automatic discovery doesn\'t find the device.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const Gap(40),
                    
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _ipController,
                            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'IP Address',
                              labelStyle: GoogleFonts.plusJakartaSans(color: colorScheme.primary),
                              hintText: '192.168.1.100',
                              hintStyle: GoogleFonts.plusJakartaSans(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              prefixIcon: Icon(LucideIcons.globe, color: colorScheme.primary),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            ),
                            keyboardType: TextInputType.number,
                            autofocus: true,
                          ),
                          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5), indent: 24, endIndent: 24),
                          TextField(
                            controller: _portController,
                            style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Port',
                              labelStyle: GoogleFonts.plusJakartaSans(color: colorScheme.primary),
                              hintText: '53318',
                              hintStyle: GoogleFonts.plusJakartaSans(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              prefixIcon: Icon(LucideIcons.hash, color: colorScheme.primary),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ),
                    
                    const Gap(40),
                    
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isConnecting ? null : _connect,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        icon: _isConnecting
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.onPrimary),
                              )
                            : const Icon(LucideIcons.link, size: 24),
                        label: Text(
                          _isConnecting ? 'Connecting...' : 'Connect',
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
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

    final parts = ip.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid IP address format')),
      );
      return;
    }

    setState(() => _isConnecting = true);

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

    ref.read(nearbyDevicesProvider.notifier).addDevice(device);

    setState(() => _isConnecting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Device added: $ip:$port')),
    );

    if (mounted) Navigator.pop(context);
  }
}
