abstract class AppConstants {
  static const String appName = 'Sendate';
  static const String appVersion = '1.0.0';

  // Transfer
  static const int defaultChunkSize = 1024 * 1024; // 1MB
  static const int maxParallelTransfers = 3;
  static const int transferTimeout = 30; // seconds
  static const int retryAttempts = 3;

  // Discovery / Ports  (each service owns a distinct port)
  static const int discoveryPort = 53317;           // UDP discovery broadcast
  static const int transferPort = 53318;             // TCP file transfer
  static const int clipboardPort = 53320;            // TCP clipboard sync
  static const int notificationSyncPort = 53321;    // TCP notification sync
  static const int persistentConnectionPort = 53322; // TCP keep-alive
  static const int messagingPort = 53323;            // TCP offline messaging
  // FIX BUG-09: browserReceiverPort was 53319, colliding with comments that
  // reserved that range for persistent-connection. Moved to 53325.
  static const int browserReceiverPort = 53325;     // HTTP browser receiver

  static const Duration discoveryInterval = Duration(seconds: 1);
  static const Duration discoveryTimeout = Duration(seconds: 10);

  // Storage
  static const String settingsBox = 'settings';
  static const String devicesBox = 'trusted_devices';
  static const String historyBox = 'transfer_history';
  static const String resumeBox = 'resume_metadata';
  static const String favoritesBox = 'favorites';
  static const String blockedBox = 'blocked_devices';
  static const String savedSelectionsBox = 'saved_selections';

  // Limits
  static const int maxMemoryUsageMB = 250;
  static const int maxAppSizeMB = 50;
}
