import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildSegment(context, ReceiveMode.public, 'Public', LucideIcons.globe, colorScheme),
          _buildSegment(context, ReceiveMode.trustedOnly, 'Trusted', LucideIcons.shieldCheck, colorScheme),
          _buildSegment(context, ReceiveMode.hidden, 'Hidden', LucideIcons.eyeOff, colorScheme),
        ],
      ),
    );
  }

  Widget _buildSegment(BuildContext context, ReceiveMode itemMode, String label, IconData icon, ColorScheme colorScheme) {
    final isSelected = mode == itemMode;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(itemMode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
