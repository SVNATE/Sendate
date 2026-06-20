import 'dart:io';

/// Centralized platform capability checks.
/// Use this instead of raw Platform.isX checks in UI code for consistency.
class PlatformCapabilities {
  PlatformCapabilities._();

  /// Whether the device has a camera for QR scanning
  static bool get hasCamera => Platform.isAndroid || Platform.isIOS;

  /// Whether Bluetooth is supported (discovery + transfer)
  static bool get hasBluetooth => Platform.isAndroid || Platform.isIOS;

  /// Whether WiFi Direct (P2P) is supported
  static bool get hasWifiDirect => Platform.isAndroid;

  /// Whether the NotificationListenerService API is available
  static bool get hasNotificationListener => Platform.isAndroid;

  /// Whether biometric authentication is supported (local_auth)
  static bool get hasBiometrics =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Whether the platform supports a foreground/background service
  static bool get hasForegroundService => Platform.isAndroid;

  /// Whether the platform supports system tray (menu bar)
  static bool get hasSystemTray =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Whether this is a mobile platform (phone/tablet)
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Whether this is a desktop platform
  static bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}
