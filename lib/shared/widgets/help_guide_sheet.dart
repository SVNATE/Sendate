import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Shows a help guide bottom sheet for a screen.
void showHelpGuide(BuildContext context, {required String title, required List<HelpItem> items}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Row(
              children: [
                Icon(LucideIcons.helpCircle, size: 20, color: Theme.of(context).colorScheme.primary),
                const Gap(10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
              itemCount: items.length,
              separatorBuilder: (_, i) => const Gap(16),
              itemBuilder: (context, index) => _HelpItemTile(item: items[index]),
            ),
          ),
        ],
      ),
    ),
  );
}

class HelpItem {
  final IconData icon;
  final String title;
  final String description;
  final Color? iconColor;

  const HelpItem({
    required this.icon,
    required this.title,
    required this.description,
    this.iconColor,
  });
}

class _HelpItemTile extends StatelessWidget {
  final HelpItem item;
  const _HelpItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (item.iconColor ?? colorScheme.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.icon, size: 20, color: item.iconColor ?? colorScheme.primary),
        ),
        const Gap(14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const Gap(4),
              Text(
                item.description,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pre-built guide content for each screen

List<HelpItem> get receiveGuideItems => [
  const HelpItem(icon: LucideIcons.radio, title: 'Stay Discoverable', description: 'Keep this screen open so other devices can find you on the same network.'),
  const HelpItem(icon: LucideIcons.qrCode, title: 'QR Code', description: 'Tap the QR button to show your code. Other devices can scan it to connect instantly.'),
  const HelpItem(icon: LucideIcons.globe, title: 'Browser Receiver', description: 'Turn on Browser Receiver to let any device send files via a web browser — no app needed on the sender.'),
  const HelpItem(icon: LucideIcons.shieldCheck, title: 'Receive Modes', description: 'Public = everyone nearby. Trusted = only paired devices. Hidden = completely invisible, connect only via QR/code/IP.'),
  const HelpItem(icon: LucideIcons.wifi, title: 'Same WiFi Network', description: 'Both devices must be on the same WiFi for auto-discovery. Transfer speeds up to 100+ MB/s.'),
  const HelpItem(icon: LucideIcons.router, title: 'WiFi Hotspot', description: 'No WiFi? Create a hotspot on one device, connect the other to it. Sendate auto-detects hotspot networks.'),
  const HelpItem(icon: LucideIcons.link, title: 'Persistent Connection', description: 'Trusted devices stay connected in the background. Clipboard syncs automatically between them.'),
];

List<HelpItem> get sendGuideItems => [
  const HelpItem(icon: LucideIcons.file, title: 'Pick Files', description: 'Tap Photos, Videos, Files, or Folders to select content. Multiple selection supported.'),
  const HelpItem(icon: LucideIcons.radar, title: 'Find Devices', description: 'Nearby devices appear automatically via WiFi, Bluetooth, and WiFi Direct. Tap Scan to refresh.'),
  const HelpItem(icon: LucideIcons.send, title: 'Send Files', description: 'Select files first, then tap a device. Confirm and encrypted transfer begins instantly.'),
  const HelpItem(icon: LucideIcons.clipboard, title: 'Clipboard Sync', description: 'Sends your clipboard text directly to the other device\'s clipboard — no .txt file. Enable auto-sync in Settings.'),
  const HelpItem(icon: LucideIcons.wifi, title: 'WiFi Transfer', description: 'Fastest method. Both devices on the same WiFi. Files are encrypted with AES-256.', iconColor: Color(0xFF22C55E)),
  const HelpItem(icon: LucideIcons.bluetooth, title: 'Bluetooth Transfer', description: 'Works without WiFi. Slower but always available. Tap BT scan in Devices.', iconColor: Color(0xFF3B82F6)),
  const HelpItem(icon: LucideIcons.repeat, title: 'Auto Convert', description: 'HEIC→JPEG, MOV→MP4 conversions happen automatically when sending to non-Apple devices.'),
];

List<HelpItem> get devicesGuideItems => [
  const HelpItem(icon: LucideIcons.shieldCheck, title: 'Trust a Device', description: 'Trusted devices auto-accept transfers and sync clipboard. Tap ⋮ → Trust.'),
  const HelpItem(icon: LucideIcons.ban, title: 'Block a Device', description: 'Blocked devices are silently rejected. Undo available.'),
  const HelpItem(icon: LucideIcons.link, title: 'Persistent Connection', description: 'Connected devices stay linked with heartbeat. Clipboard syncs in real-time between them.'),
  const HelpItem(icon: LucideIcons.messageCircle, title: 'Offline Messages', description: 'Send text messages to any device. Delivered automatically when both come online.'),
  const HelpItem(icon: LucideIcons.scanLine, title: 'QR Scan', description: 'Scan a Sendate QR code to connect across different networks instantly.'),
  const HelpItem(icon: LucideIcons.globe, title: 'Manual IP', description: 'Enter IP address directly when auto-discovery fails. Useful behind strict firewalls.'),
  const HelpItem(icon: LucideIcons.bluetooth, title: 'Bluetooth', description: 'Discover nearby Bluetooth devices. Works without any WiFi connection.'),
  const HelpItem(icon: LucideIcons.wifi, title: 'WiFi Direct', description: 'P2P connection without a router. One device creates a group, the other joins.'),
  const HelpItem(icon: LucideIcons.alertTriangle, title: 'Troubleshooting', description: 'Device not found? Check: same WiFi, firewall rules, router client isolation. Try Hotspot or Manual IP as fallback.', iconColor: Color(0xFFF59E0B)),
];

List<HelpItem> get historyGuideItems => [
  const HelpItem(icon: LucideIcons.clock, title: 'Transfer History', description: 'All transfers are saved here permanently — survives app restart.'),
  const HelpItem(icon: LucideIcons.clipboard, title: 'Clipboard History', description: 'Received clipboard entries also appear here with text preview.'),
  const HelpItem(icon: LucideIcons.trash2, title: 'Delete', description: 'Swipe left to delete one item. Trash icon clears all.'),
  const HelpItem(icon: LucideIcons.chevronRight, title: 'Details', description: 'Tap any transfer for full info — file, size, speed, duration, device.'),
];

List<HelpItem> get settingsGuideItems => [
  const HelpItem(icon: LucideIcons.user, title: 'Device Name', description: 'The name other devices see when they discover you.'),
  const HelpItem(icon: LucideIcons.folderOutput, title: 'Save Location', description: 'Choose where received files are saved — Downloads, Documents, or a custom folder.'),
  const HelpItem(icon: LucideIcons.repeat, title: 'Auto Convert', description: 'Automatically converts incompatible files (HEIC→JPEG, MOV→MP4) before sending.'),
  const HelpItem(icon: LucideIcons.zap, title: 'Auto Accept', description: 'When enabled, files from trusted devices are accepted without prompting.'),
  const HelpItem(icon: LucideIcons.clipboard, title: 'Clipboard Sync', description: 'Auto-sync clipboard with connected devices. Copy on one, paste on another.'),
  const HelpItem(icon: LucideIcons.lock, title: 'App Lock', description: 'Require fingerprint/face/PIN to open Sendate.'),
  const HelpItem(icon: LucideIcons.timer, title: 'Transfer Expiry', description: 'Auto-delete received files after 1 hour, 1 day, 7 days, or keep forever.'),
  const HelpItem(icon: LucideIcons.shield, title: 'Encryption', description: 'All transfers use AES-256-GCM encryption. Session keys are ephemeral.'),
];
