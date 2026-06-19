import '../foreground/android_foreground_service.dart';

/// Background service helper.
/// Android: Uses a proper foreground service (KDE Connect style) with persistent notification.
/// Desktop: System tray keeps the process alive when window is closed.
class BackgroundServiceHelper {
  static Future<void> initialize() async {
    if (AndroidForegroundService.isSupported) {
      await AndroidForegroundService.instance.start();
    }
    // Desktop: handled by SystemTrayService + window_manager (close = hide)
  }

  static Future<void> stop() async {
    if (AndroidForegroundService.isSupported) {
      await AndroidForegroundService.instance.stop();
    }
  }
}
