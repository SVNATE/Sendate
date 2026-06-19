import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../screens/receive_screen.dart';

class ReceiveModeSelector extends StatelessWidget {
  final ReceiveMode mode;
  final ValueChanged<ReceiveMode> onChanged;

  const ReceiveModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReceiveMode>(
      segments: [
        ButtonSegment(
          value: ReceiveMode.public,
          label: Text('Public'),
          icon: Icon(LucideIcons.globe),
        ),
        ButtonSegment(
          value: ReceiveMode.trustedOnly,
          label: Text('Trusted'),
          icon: Icon(LucideIcons.shieldCheck),
        ),
        ButtonSegment(
          value: ReceiveMode.hidden,
          label: Text('Hidden'),
          icon: Icon(LucideIcons.eyeOff),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
