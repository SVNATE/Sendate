abstract class AppConstants {
  static const String appName = 'Sendate';
  static const String appVersion = '1.0.0';

  // Transfer
  static const int defaultChunkSize = 1024 * 1024; // 1MB
  static const int maxParallelTransfers = 3;
  static const int transferTimeout = 30; // seconds
  static const int retryAttempts = 3;

  // Discovery
  static const int discoveryPort = 53317;
  static const int transferPort = 53318;
  static const int browserReceiverPort = 53319;
  static const Duration discoveryInterval = Duration(seconds: 1);
  static const Duration discoveryTimeout = Duration(seconds: 10);

  // Storage
  static const String settingsBox = 'settings';
  static const String devicesBox = 'trusted_devices';
  static const String historyBox = 'transfer_history';
  static const String resumeBox = 'resume_metadata';
  static const String favoritesBox = 'favorites';
  static const String blockedBox = 'blocked_devices';

  // Limits
  static const int maxMemoryUsageMB = 250;
  static const int maxAppSizeMB = 50;
}
