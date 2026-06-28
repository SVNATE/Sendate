import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/widgets/device_avatar.dart';

class DeviceCardWidget extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback? onCopyAddress;

  const DeviceCardWidget({
    super.key,
    required this.device,
    this.onCopyAddress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          DeviceAvatar(device: device, size: 56),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Gap(4),
                GestureDetector(
                  onTap: onCopyAddress,
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.fingerprint,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          device.fingerprint,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopyAddress,
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
            ),
            icon: Icon(LucideIcons.copy, size: 18, color: colorScheme.primary),
            tooltip: 'Copy fingerprint',
          ),
        ],
      ),
    );
  }
}
