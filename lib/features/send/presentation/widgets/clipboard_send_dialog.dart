import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/providers/clipboard_provider.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/widgets/device_avatar.dart';

/// Clipboard send dialog — sends text DIRECTLY to device clipboard
/// (no .txt file, no approval needed on receiver, instant paste)
class ClipboardSendDialog extends ConsumerStatefulWidget {
  const ClipboardSendDialog({super.key});

  @override
  ConsumerState<ClipboardSendDialog> createState() => _ClipboardSendDialogState();
}

class _ClipboardSendDialogState extends ConsumerState<ClipboardSendDialog> {
  String? _clipboardText;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadClipboard();
  }

  Future<void> _loadClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    setState(() {
      _clipboardText = data?.text;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nearbyDevices = ref.watch(allNearbyDevicesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 104),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send Clipboard',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Gap(16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            constraints: const BoxConstraints(maxHeight: 100),
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _clipboardText ?? '(empty clipboard)',
                    style: TextStyle(
                      fontSize: 13,
                      color: _clipboardText != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const Gap(20),
          Text('Send to:', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const Gap(8),
          if (nearbyDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No nearby devices', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            )
          else
            ...nearbyDevices.take(5).map(
              (device) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: DeviceAvatar(device: device, size: 36),
                title: Text(device.name, style: const TextStyle(fontSize: 14)),
                trailing: Icon(LucideIcons.send, size: 16, color: colorScheme.primary),
                onTap: _clipboardText != null ? () => _sendClipboard(device) : null,
              ),
            ),
          const Gap(8),
        ],
      ),
    );
  }

  /// Send clipboard DIRECTLY via clipboard protocol — no file, no approval needed
  Future<void> _sendClipboard(DeviceModel device) async {
    if (_clipboardText == null || _clipboardText!.isEmpty) return;

    final clipboardService = ref.read(clipboardSyncServiceProvider);
    final success = await clipboardService.sendClipboardTo(device, content: _clipboardText!);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Clipboard sent to ${device.name}' : 'Failed — device may be offline'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
