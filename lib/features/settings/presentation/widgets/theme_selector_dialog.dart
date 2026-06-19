import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ThemeSelectorDialog extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onSelect;

  const ThemeSelectorDialog({
    super.key,
    required this.currentMode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Appearance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThemeOption(
            icon: LucideIcons.sun,
            title: 'Light',
            selected: currentMode == ThemeMode.light,
            onTap: () {
              onSelect(ThemeMode.light);
              Navigator.pop(context);
            },
          ),
          _ThemeOption(
            icon: LucideIcons.moon,
            title: 'Dark',
            selected: currentMode == ThemeMode.dark,
            onTap: () {
              onSelect(ThemeMode.dark);
              Navigator.pop(context);
            },
          ),
          _ThemeOption(
            icon: LucideIcons.monitor,
            title: 'System',
            selected: currentMode == ThemeMode.system,
            onTap: () {
              onSelect(ThemeMode.system);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: selected ? colorScheme.primary : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? colorScheme.primary : null,
        ),
      ),
      trailing: selected
          ? Icon(LucideIcons.check, color: colorScheme.primary)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
