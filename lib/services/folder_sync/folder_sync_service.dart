import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:hive/hive.dart';

import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../../shared/models/sendate_file.dart';
import '../transfer/transfer_service.dart';

enum SyncMode { oneWay, twoWay, manual }
enum ConflictResolution { keepBoth, replace, skip }

class FolderSyncConfig {
  final String id;
  final String localPath;
  final String deviceId;
  final String deviceName;
  final SyncMode mode;
  final ConflictResolution conflictResolution;
  final Duration? interval; // null = manual only

  FolderSyncConfig({
    required this.id,
    required this.localPath,
    required this.deviceId,
    required this.deviceName,
    this.mode = SyncMode.oneWay,
    this.conflictResolution = ConflictResolution.keepBoth,
    this.interval,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'localPath': localPath, 'deviceId': deviceId,
    'deviceName': deviceName, 'mode': mode.name,
    'conflictResolution': conflictResolution.name,
    'intervalMinutes': interval?.inMinutes,
  };

  factory FolderSyncConfig.fromMap(Map<String, dynamic> map) => FolderSyncConfig(
    id: map['id'] as String,
    localPath: map['localPath'] as String,
    deviceId: map['deviceId'] as String,
    deviceName: map['deviceName'] as String? ?? '',
    mode: SyncMode.values.firstWhere((m) => m.name == map['mode'], orElse: () => SyncMode.oneWay),
    conflictResolution: ConflictResolution.values.firstWhere((c) => c.name == map['conflictResolution'], orElse: () => ConflictResolution.keepBoth),
    interval: map['intervalMinutes'] != null ? Duration(minutes: map['intervalMinutes'] as int) : null,
  );
}

/// Folder sync service — watches a local folder and syncs changes to a target device.
class FolderSyncService {
  static const _boxName = 'folder_sync';
  final _log = const AppLogger('FolderSync');
  final Map<String, StreamSubscription> _watchers = {};
  final Map<String, Timer> _scheduledSyncs = {};
  TransferService? transferService;

  /// Get all sync configurations
  Future<List<FolderSyncConfig>> getConfigs() async {
    final box = await Hive.openBox(_boxName);
    return box.values.map((v) => FolderSyncConfig.fromMap(Map<String, dynamic>.from(v as Map))).toList();
  }

  /// Add a new sync configuration
  Future<void> addConfig(FolderSyncConfig config) async {
    final box = await Hive.openBox(_boxName);
    await box.put(config.id, config.toMap());
    _startWatching(config);
  }

  /// Remove a sync configuration
  Future<void> removeConfig(String id) async {
    _stopWatching(id);
    final box = await Hive.openBox(_boxName);
    await box.delete(id);
  }

  /// Start watching all configured folders
  Future<void> startAll() async {
    final configs = await getConfigs();
    for (final config in configs) {
      _startWatching(config);
    }
  }

  /// Stop all watchers
  void stopAll() {
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
    for (final timer in _scheduledSyncs.values) {
      timer.cancel();
    }
    _scheduledSyncs.clear();
  }

  void _startWatching(FolderSyncConfig config) {
    _stopWatching(config.id);

    final dir = Directory(config.localPath);
    if (!dir.existsSync()) return;

    // Watch for file changes
    final subscription = dir.watch(recursive: true).listen((event) {
      if (event is FileSystemCreateEvent || event is FileSystemModifyEvent) {
        _onFileChanged(config, event.path);
      }
    });
    _watchers[config.id] = subscription;

    // Schedule periodic sync if configured
    if (config.interval != null) {
      _scheduledSyncs[config.id] = Timer.periodic(config.interval!, (_) {
        syncFolder(config);
      });
    }
  }

  void _stopWatching(String id) {
    _watchers[id]?.cancel();
    _watchers.remove(id);
    _scheduledSyncs[id]?.cancel();
    _scheduledSyncs.remove(id);
  }

  void _onFileChanged(FolderSyncConfig config, String filePath) {
    if (config.mode == SyncMode.manual) return;
    // Debounce: wait a bit before syncing
    Future.delayed(const Duration(seconds: 2), () {
      _syncFile(config, filePath);
    });
  }

  /// Sync entire folder
  Future<SyncResult> syncFolder(FolderSyncConfig config) async {
    final dir = Directory(config.localPath);
    if (!await dir.exists()) return SyncResult(synced: 0, skipped: 0, errors: 0);

    int synced = 0, skipped = 0, errors = 0;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      try {
        await _syncFile(config, entity.path);
        synced++;
      } catch (e) {
        _log.debug('Failed to sync file ${entity.path}: $e');
        errors++;
      }
    }

    return SyncResult(synced: synced, skipped: skipped, errors: errors);
  }

  Future<void> _syncFile(FolderSyncConfig config, String filePath) async {
    if (transferService == null) return;
    final file = File(filePath);
    if (!await file.exists()) return;

    // Create target device model for transfer
    final target = DeviceModel(
      id: config.deviceId,
      name: config.deviceName,
      deviceType: DeviceType.unknown,
      fingerprint: '',
    );

    final sendateFile = SendateFile(
      name: file.uri.pathSegments.last,
      size: await file.length(),
      path: filePath,
    );

    await transferService!.sendFile(file: sendateFile, target: target);
  }

  /// Compute file hash for diff detection (SHA-256)
  Future<String> fileHash(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return crypto_pkg.sha256.convert(bytes).toString();
  }

  void dispose() => stopAll();
}

class SyncResult {
  final int synced;
  final int skipped;
  final int errors;
  SyncResult({required this.synced, required this.skipped, required this.errors});
}
