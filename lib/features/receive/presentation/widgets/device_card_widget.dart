import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
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

    return Card(
      child: Padding(
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Gap(4),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.fingerprint,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const Gap(4),
                      Expanded(
                        child: Text(
                          device.fingerprint,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCopyAddress,
              icon: Icon(LucideIcons.copy),
              tooltip: 'Copy fingerprint',
            ),
          ],
        ),
      ),
    );
  }
}
