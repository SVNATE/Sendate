import 'dart:io';

/// Platform-specific firewall and connectivity helpers.
/// Addresses the common issue of Windows devices not connecting
/// because firewall blocks UDP broadcast on unknown ports.
class FirewallHelper {
  /// Check if we're on Windows and offer firewall fix
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;

  /// Get platform-specific connection troubleshooting instructions
  static List<TroubleshootStep> getTroubleshootingSteps() {
    if (Platform.isWindows) {
      return [
        TroubleshootStep(
          title: 'Allow Sendate through Windows Firewall',
          description: 'Windows Firewall may block device discovery.',
          instruction: 'Go to Settings → Privacy & Security → Windows Security → Firewall → Allow an app through firewall → Add Sendate',
          canAutoFix: true,
        ),
        TroubleshootStep(
          title: 'Check Network Profile',
          description: 'Your network must be set to "Private" for discovery.',
          instruction: 'Settings → Network & Internet → WiFi → [Your Network] → Set to Private',
          canAutoFix: false,
        ),
        TroubleshootStep(
          title: 'Disable VPN',
          description: 'VPNs can block local network traffic.',
          instruction: 'Temporarily disconnect your VPN and try again.',
          canAutoFix: false,
        ),
      ];
    } else if (Platform.isMacOS) {
      return [
        TroubleshootStep(
          title: 'Allow Incoming Connections',
          description: 'macOS Firewall may block Sendate.',
          instruction: 'System Settings → Network → Firewall → Options → Add Sendate to allowed apps',
          canAutoFix: false,
        ),
        TroubleshootStep(
          title: 'Same Network',
          description: 'Both devices must be on the same WiFi network.',
          instruction: 'Check WiFi name matches on both devices.',
          canAutoFix: false,
        ),
      ];
    } else if (Platform.isLinux) {
      return [
        TroubleshootStep(
          title: 'Open Firewall Ports',
          description: 'Open UDP/TCP ports 53317-53320.',
          instruction: 'Run: sudo ufw allow 53317:53320/tcp && sudo ufw allow 53317:53320/udp',
          canAutoFix: true,
        ),
      ];
    } else {
      // Android/iOS
      return [
        TroubleshootStep(
          title: 'Same Network',
          description: 'Both devices must be on the same WiFi.',
          instruction: 'Or create a hotspot on one device and connect the other.',
          canAutoFix: false,
        ),
        TroubleshootStep(
          title: 'Router Client Isolation',
          description: 'Some routers block device-to-device communication.',
          instruction: 'Try using Hotspot mode or WiFi Direct instead.',
          canAutoFix: false,
        ),
      ];
    }
  }

  /// Attempt to auto-fix firewall on Windows
  /// Runs: netsh advfirewall firewall add rule name="Sendate" ...
  static Future<bool> autoFixWindowsFirewall() async {
    if (!Platform.isWindows) return false;

    try {
      // Add TCP rule
      await Process.run('netsh', [
        'advfirewall', 'firewall', 'add', 'rule',
        'name=Sendate TCP', 'dir=in', 'action=allow',
        'protocol=TCP', 'localport=53317-53320',
      ]);
      // Add UDP rule
      await Process.run('netsh', [
        'advfirewall', 'firewall', 'add', 'rule',
        'name=Sendate UDP', 'dir=in', 'action=allow',
        'protocol=UDP', 'localport=53317-53320',
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Auto-fix Linux firewall (ufw)
  static Future<bool> autoFixLinuxFirewall() async {
    if (!Platform.isLinux) return false;

    try {
      await Process.run('sudo', ['ufw', 'allow', '53317:53320/tcp']);
      await Process.run('sudo', ['ufw', 'allow', '53317:53320/udp']);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class TroubleshootStep {
  final String title;
  final String description;
  final String instruction;
  final bool canAutoFix;

  TroubleshootStep({
    required this.title,
    required this.description,
    required this.instruction,
    required this.canAutoFix,
  });
}
