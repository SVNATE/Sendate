import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';

/// Local storage service using Hive.
/// No cloud, no remote backend, no user accounts.
class HiveStorageService {
  Box get _settingsBox => Hive.box(AppConstants.settingsBox);
  Box get _devicesBox => Hive.box(AppConstants.devicesBox);
  Box get _historyBox => Hive.box(AppConstants.historyBox);
  Box get _resumeBox => Hive.box(AppConstants.resumeBox);

  // --- Settings ---

  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  // --- Device Name ---

  String get deviceName =>
      getSetting<String>('device_name') ?? 'My Device';

  Future<void> setDeviceName(String name) =>
      saveSetting('device_name', name);

  // --- Trusted Devices ---

  Future<void> saveTrustedDevice(Map<String, dynamic> device) async {
    await _devicesBox.put(device['id'], device);
  }

  Future<void> removeTrustedDevice(String id) async {
    await _devicesBox.delete(id);
  }

  List<Map<String, dynamic>> getTrustedDevices() {
    return _devicesBox.values.cast<Map<String, dynamic>>().toList();
  }

  // --- Transfer History ---

  Future<void> addHistoryRecord(Map<String, dynamic> record) async {
    await _historyBox.add(record);
  }

  List<Map<String, dynamic>> getHistory() {
    return _historyBox.values.cast<Map<String, dynamic>>().toList();
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  // --- Resume Metadata ---

  Future<void> saveResumeData(String transferId, Map<String, dynamic> data) async {
    await _resumeBox.put(transferId, data);
  }

  Map<String, dynamic>? getResumeData(String transferId) {
    return _resumeBox.get(transferId) as Map<String, dynamic>?;
  }

  Future<void> clearResumeData(String transferId) async {
    await _resumeBox.delete(transferId);
  }
}
