import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/device_model.dart';

class DeviceAvatar extends StatelessWidget {
  final DeviceModel device;
  final double size;
  final bool showTrustBadge;

  const DeviceAvatar({
    super.key,
    required this.device,
    this.size = 48,
    this.showTrustBadge = false,
  });

  IconData get _icon => switch (device.deviceType) {
        DeviceType.phone => LucideIcons.smartphone,
        DeviceType.tablet => LucideIcons.tablet,
        DeviceType.laptop => LucideIcons.laptop,
        DeviceType.desktop => LucideIcons.monitor,
        DeviceType.tv => LucideIcons.tv,
        DeviceType.unknown => LucideIcons.helpCircle,
      };

  Color _trustColor(BuildContext context) => switch (device.trustLevel) {
        TrustLevel.trusted => const Color(0xFF22C55E),
        TrustLevel.known => const Color(0xFF3B82F6),
        TrustLevel.unknown => Theme.of(context).colorScheme.outline,
        TrustLevel.blocked => const Color(0xFFEF4444),
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(size * 0.3),
            ),
            child: Icon(
              _icon,
              size: size * 0.5,
              color: colorScheme.primary,
            ),
          ),
          if (showTrustBadge)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  color: _trustColor(context),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
