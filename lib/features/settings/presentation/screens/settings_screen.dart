import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/clipboard_provider.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/notification_sync_provider.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';
import '../../../settings/presentation/screens/app_lock_screen.dart';
import '../widgets/device_name_dialog.dart';
import '../widgets/theme_selector_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceName = ref.watch(deviceNameProvider);
    final autoConvert = ref.watch(autoConvertProvider);
    final autoAccept = ref.watch(autoAcceptProvider);
    final saveLocation = ref.watch(saveLocationProvider);
    final themeMode = ref.watch(themeModeProvider);
    final hiddenMode = ref.watch(hiddenModeProvider);
    final expiry = ref.watch(transferExpiryProvider);

    final themeName = switch (themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System',
    };

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Settings'),
            actions: [
              IconButton(
                onPressed: () => showHelpGuide(context, title: 'Settings Help', items: settingsGuideItems),
                icon: Icon(LucideIcons.helpCircle),
                tooltip: 'Help',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.list(
              children: [
                const Gap(8),
                _SettingsSection(
                  title: 'General',
                  children: [
                    _SettingsItem(
                      icon: LucideIcons.user,
                      title: 'Device Name',
                      subtitle: deviceName,
                      onTap: () => _showDeviceNameDialog(context, ref),
                    ),
                    _SettingsItem(
                      icon: LucideIcons.palette,
                      title: 'Appearance',
                      subtitle: themeName,
                      onTap: () => _showThemeDialog(context, ref),
                    ),
                  ],
                ),
                const Gap(24),
                _SettingsSection(
                  title: 'Transfer',
                  children: [
                    _SettingsItem(
                      icon: LucideIcons.folderOutput,
                      title: 'Save Location',
                      subtitle: saveLocation,
                      onTap: () => _showSaveLocationDialog(context, ref),
                    ),
                    _SettingsToggleItem(
                      icon: LucideIcons.repeat,
                      title: 'Auto Convert',
                      subtitle: 'Convert incompatible files automatically',
                      value: autoConvert,
                      onChanged: (_) =>
                          ref.read(autoConvertProvider.notifier).toggle(),
                    ),
                    _SettingsToggleItem(
                      icon: LucideIcons.zap,
                      title: 'Auto-Accept All',
                      subtitle: 'Accept files from any device without prompting',
                      value: autoAccept,
                      onChanged: (_) =>
                          ref.read(autoAcceptProvider.notifier).toggle(),
                    ),
                    _SettingsItem(
                      icon: LucideIcons.timer,
                      title: 'File Expiry',
                      subtitle: _expiryLabel(expiry),
                      onTap: () => _showExpiryDialog(context, ref),
                    ),
                    _SettingsToggleItem(
                      icon: LucideIcons.clipboard,
                      title: 'Clipboard Sync',
                      subtitle: 'Auto-sync clipboard with connected devices',
                      value: ref.watch(clipboardAutoSyncProvider),
                      onChanged: (_) =>
                          ref.read(clipboardAutoSyncProvider.notifier).toggle(),
                    ),
                    // Notification Sync only available on Android (requires NotificationListenerService)
                    if (PlatformCapabilities.hasNotificationListener) ...[
                      _SettingsToggleItem(
                        icon: LucideIcons.bell,
                        title: 'Notification Sync',
                        subtitle: 'Mirror phone notifications to connected devices',
                        value: ref.watch(notificationSyncEnabledProvider),
                        onChanged: (_) =>
                            ref.read(notificationSyncEnabledProvider.notifier).toggle(),
                      ),
                      _SettingsItem(
                        icon: LucideIcons.bellRing,
                        title: 'Notification Access',
                        subtitle: 'Grant permission to read notifications',
                        onTap: () => _openNotificationAccessSettings(ref),
                      ),
                    ],
                  ],
                ),
                const Gap(24),
                _SettingsSection(
                  title: 'Security',
                  children: [
                    // App Lock only on platforms with biometric support
                    if (PlatformCapabilities.hasBiometrics)
                      _SettingsToggleItem(
                        icon: LucideIcons.lock,
                        title: 'App Lock',
                        subtitle: 'Require authentication to open',
                        value: ref.watch(appLockEnabledProvider),
                        onChanged: (_) =>
                            ref.read(appLockEnabledProvider.notifier).toggle(),
                      ),
                    _SettingsItem(
                      icon: LucideIcons.shield,
                      title: 'Encryption',
                      subtitle: 'TLS 1.3 + AES-256',
                      onTap: () => _showEncryptionInfo(context),
                    ),
                    _SettingsToggleItem(
                      icon: LucideIcons.eyeOff,
                      title: 'Hidden Mode',
                      subtitle: hiddenMode
                          ? 'Invisible — share QR or code to connect'
                          : 'Appear to nearby devices',
                      value: hiddenMode,
                      onChanged: (_) => _toggleHiddenMode(ref),
                    ),
                  ],
                ),
                const Gap(24),
                _SettingsSection(
                  title: 'Tools',
                  children: [
                    _SettingsItem(
                      icon: LucideIcons.folderSync,
                      title: 'Folder Sync',
                      subtitle: 'Auto-sync folders with nearby devices',
                      onTap: () => context.push('/folder-sync'),
                    ),
                  ],
                ),
                const Gap(24),
                _SettingsSection(
                  title: 'About',
                  children: [
                    _SettingsItem(
                      icon: LucideIcons.info,
                      title: 'Version',
                      subtitle: '1.0.0',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: LucideIcons.fileText,
                      title: 'Licenses',
                      subtitle: 'Open source licenses',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Sendate',
                        applicationVersion: '1.0.0',
                      ),
                    ),
                  ],
                ),
                const Gap(40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeviceNameDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => DeviceNameDialog(
        currentName: ref.read(deviceNameProvider),
        onSave: (name) {
          ref.read(deviceNameProvider.notifier).setDeviceName(name);
        },
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => ThemeSelectorDialog(
        currentMode: ref.read(themeModeProvider),
        onSelect: (mode) {
          ref.read(themeModeProvider.notifier).setThemeMode(mode);
        },
      ),
    );
  }

  void _showSaveLocationDialog(BuildContext context, WidgetRef ref) {
    final options = ['Downloads', 'Documents', 'Pictures', 'Custom Folder'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Save Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ...options.map(
              (option) => ListTile(
                title: Text(option),
                leading: Icon(
                  option == 'Custom Folder'
                      ? LucideIcons.folderOpen
                      : LucideIcons.folder,
                ),
                trailing: ref.read(saveLocationProvider) == option
                    ? Icon(LucideIcons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (option == 'Custom Folder') {
                    final path =
                        await FilePicker.platform.getDirectoryPath();
                    if (path != null) {
                      ref
                          .read(saveLocationProvider.notifier)
                          .setSaveLocation(path);
                    }
                  } else {
                    ref
                        .read(saveLocationProvider.notifier)
                        .setSaveLocation(option);
                  }
                },
              ),
            ),
            const Gap(16),
          ],
        ),
      ),
    );
  }

  void _showEncryptionInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encryption'),
        content: const Text(
          'All transfers use TLS 1.3 for transport encryption '
          'and AES-256-GCM for payload encryption.\n\n'
          'Each session generates ephemeral keys that are never stored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _toggleHiddenMode(WidgetRef ref) {
    final notifier = ref.read(hiddenModeProvider.notifier);
    final newVal = !ref.read(hiddenModeProvider);
    notifier.toggle();
    // Wire directly to discovery service
    ref.read(discoveryServiceProvider).hiddenMode = newVal;
  }

  String _expiryLabel(Duration? expiry) {
    if (expiry == null) return 'Keep forever';
    if (expiry.inHours == 1) return '1 hour';
    if (expiry.inHours < 24) return '${expiry.inHours} hours';
    if (expiry.inDays == 1) return '1 day';
    return '${expiry.inDays} days';
  }

  void _showExpiryDialog(BuildContext context, WidgetRef ref) {
    final options = <MapEntry<String, Duration?>>[
      const MapEntry('1 hour', Duration(hours: 1)),
      const MapEntry('1 day', Duration(hours: 24)),
      const MapEntry('7 days', Duration(days: 7)),
      const MapEntry('30 days', Duration(days: 30)),
      const MapEntry('Keep forever', null),
    ];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'File Expiry',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ...options.map(
              (opt) => ListTile(
                title: Text(opt.key),
                leading: Icon(opt.value == null
                    ? LucideIcons.infinity
                    : LucideIcons.timer),
                trailing: ref.read(transferExpiryProvider) == opt.value
                    ? Icon(LucideIcons.check,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(transferExpiryProvider.notifier)
                      .setExpiry(opt.value);
                },
              ),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _openNotificationAccessSettings(WidgetRef ref) {
    ref.read(notificationSyncServiceProvider).openPermissionSettings();
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const Gap(12),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, size: 20, color: colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

class _SettingsToggleItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, size: 20, color: colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
