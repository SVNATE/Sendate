import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/utils/platform_capabilities.dart';
import '../../../../shared/providers/clipboard_provider.dart';
import '../../../../shared/providers/discovery_provider.dart';
import '../../../../shared/providers/notification_sync_provider.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../../shared/widgets/help_guide_sheet.dart';
import 'app_lock_screen.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Settings',
                    style: GoogleFonts.outfit(
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => showHelpGuide(context, title: 'Settings Help', items: settingsGuideItems),
                    icon: Icon(LucideIcons.helpCircle, color: colorScheme.onSurfaceVariant),
                    tooltip: 'Help',
                  ),
                ],
              ),
            ],
          ),
          const Gap(40),

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
          const Gap(32),

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
                onChanged: (_) => ref.read(autoConvertProvider.notifier).toggle(),
              ),
              _SettingsToggleItem(
                icon: LucideIcons.zap,
                title: 'Auto-Accept All',
                subtitle: 'Accept files without prompting',
                value: autoAccept,
                onChanged: (_) => ref.read(autoAcceptProvider.notifier).toggle(),
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
                onChanged: (_) => ref.read(clipboardAutoSyncProvider.notifier).toggle(),
              ),
              if (PlatformCapabilities.hasNotificationListener) ...[
                _SettingsToggleItem(
                  icon: LucideIcons.bell,
                  title: 'Notification Sync',
                  subtitle: 'Mirror phone notifications',
                  value: ref.watch(notificationSyncEnabledProvider),
                  onChanged: (_) => ref.read(notificationSyncEnabledProvider.notifier).toggle(),
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
          const Gap(32),

          _SettingsSection(
            title: 'Security',
            children: [
              if (PlatformCapabilities.hasBiometrics)
                _SettingsToggleItem(
                  icon: LucideIcons.lock,
                  title: 'App Lock',
                  subtitle: 'Require authentication to open',
                  value: ref.watch(appLockEnabledProvider),
                  onChanged: (_) => ref.read(appLockEnabledProvider.notifier).toggle(),
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
                subtitle: hiddenMode ? 'Invisible to nearby devices' : 'Appear to nearby devices',
                value: hiddenMode,
                onChanged: (_) => _toggleHiddenMode(ref),
              ),
            ],
          ),
          const Gap(32),

          _SettingsSection(
            title: 'Tools',
            children: [
              _SettingsItem(
                icon: LucideIcons.folderSync,
                title: 'Folder Sync',
                subtitle: 'Auto-sync folders with devices',
                onTap: () => context.push('/folder-sync'),
              ),
            ],
          ),
          const Gap(32),

          _SettingsSection(
            title: 'About',
            children: [
              _SettingsItem(
                icon: LucideIcons.shieldCheck,
                title: 'Privacy Policy',
                subtitle: 'How we protect your data',
                onTap: () => _openLegalDocument(context, 'Privacy Policy', 'assets/docs/PRIVACY_POLICY.md'),
              ),
              _SettingsItem(
                icon: LucideIcons.scroll,
                title: 'Terms & Conditions',
                subtitle: 'Rules and guidelines',
                onTap: () => _openLegalDocument(context, 'Terms & Conditions', 'assets/docs/TERMS_AND_CONDITIONS.md'),
              ),
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
          const Gap(120), // Extra padding to clear floating nav bar
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 104),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Save Location',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const Gap(16),
              ...options.map(
                (option) {
                  final isSelected = ref.read(saveLocationProvider) == option;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(
                      option,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    leading: Icon(
                      option == 'Custom Folder' ? LucideIcons.folderOpen : LucideIcons.folder,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    trailing: isSelected
                        ? Icon(LucideIcons.check, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (option == 'Custom Folder') {
                        final path = await FilePicker.platform.getDirectoryPath();
                        if (path != null) {
                          ref.read(saveLocationProvider.notifier).setSaveLocation(path);
                        }
                      } else {
                        ref.read(saveLocationProvider.notifier).setSaveLocation(option);
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showEncryptionInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 104),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.shieldCheck, size: 48, color: Theme.of(context).colorScheme.primary),
              ),
              const Gap(24),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'End-to-End Encryption',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Gap(16),
              Text(
                'All transfers use TLS 1.3 for transport encryption and AES-256-GCM for payload encryption.\n\nEach session generates ephemeral keys that are never stored on disk or transmitted in plaintext.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Gap(32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text('Understood', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _toggleHiddenMode(WidgetRef ref) {
    final notifier = ref.read(hiddenModeProvider.notifier);
    final newVal = !ref.read(hiddenModeProvider);
    notifier.toggle();
    ref.read(discoveryServiceProvider).hiddenMode = newVal;
  }

  void _openLegalDocument(BuildContext context, String title, String assetPath) async {
    try {
      final content = await rootBundle.loadString(assetPath);
      if (!context.mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 104),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Gap(24),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const Gap(24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load $title')),
        );
      }
    }
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 104),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'File Expiry',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const Gap(16),
              ...options.map(
                (opt) {
                  final isSelected = ref.read(transferExpiryProvider) == opt.value;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(
                      opt.key,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    leading: Icon(
                      opt.value == null ? LucideIcons.infinity : LucideIcons.timer,
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    trailing: isSelected
                        ? Icon(LucideIcons.check, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(transferExpiryProvider.notifier).setExpiry(opt.value);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ),
        ),
        const Gap(16),
        Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: colorScheme.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: colorScheme.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      onTap: () => onChanged(!value),
    );
  }
}
