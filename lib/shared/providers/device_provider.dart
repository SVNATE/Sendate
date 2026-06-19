import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../models/device_model.dart';

/// Current device info
final currentDeviceProvider = StateProvider<DeviceModel?>((ref) => null);

/// Trusted devices — persisted in Hive
final trustedDevicesProvider =
    StateNotifierProvider<TrustedDevicesNotifier, List<DeviceModel>>(
  (ref) => TrustedDevicesNotifier(),
);

class TrustedDevicesNotifier extends StateNotifier<List<DeviceModel>> {
  TrustedDevicesNotifier() : super([]) {
    _load();
  }

  Box get _box => Hive.box(AppConstants.devicesBox);

  void _load() {
    try {
      final data = _box.values.toList();
      state = data.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return DeviceModel(
          id: map['id'] as String,
          name: map['name'] as String? ?? 'Unknown',
          deviceType: _parseDeviceType(map['deviceType'] as String?),
          fingerprint: map['fingerprint'] as String? ?? '',
          ipAddress: map['ipAddress'] as String?,
          port: map['port'] as int?,
          trustLevel: TrustLevel.trusted,
        );
      }).toList();
    } catch (e) {
      debugPrint('[DeviceProvider] Failed to load trusted devices: $e');
      state = [];
    }
  }

  void addDevice(DeviceModel device) {
    final trusted = device.copyWith(trustLevel: TrustLevel.trusted);
    state = [...state.where((d) => d.id != device.id), trusted];
    _box.put(device.id, {
      'id': device.id,
      'name': device.name,
      'deviceType': device.deviceType.name,
      'fingerprint': device.fingerprint,
      'ipAddress': device.ipAddress,
      'port': device.port,
    });
  }

  void removeDevice(String deviceId) {
    state = state.where((d) => d.id != deviceId).toList();
    _box.delete(deviceId);
  }

  bool isTrusted(String deviceId) {
    return state.any((d) => d.id == deviceId);
  }

  DeviceType _parseDeviceType(String? type) => switch (type) {
        'phone' => DeviceType.phone,
        'tablet' => DeviceType.tablet,
        'laptop' => DeviceType.laptop,
        'desktop' => DeviceType.desktop,
        'tv' => DeviceType.tv,
        _ => DeviceType.unknown,
      };
}

/// Blocked devices — persisted in Hive
final blockedDevicesProvider =
    StateNotifierProvider<BlockedDevicesNotifier, List<String>>(
  (ref) => BlockedDevicesNotifier(),
);

class BlockedDevicesNotifier extends StateNotifier<List<String>> {
  BlockedDevicesNotifier() : super([]) {
    _load();
  }

  Box get _box => Hive.box(AppConstants.blockedBox);

  void _load() {
    try {
      state = _box.values.cast<String>().toList();
    } catch (e) {
      debugPrint('[DeviceProvider] Failed to load blocked devices: $e');
      state = [];
    }
  }

  void block(String deviceId) {
    if (!state.contains(deviceId)) {
      state = [...state, deviceId];
      _box.add(deviceId);
    }
  }

  void unblock(String deviceId) {
    state = state.where((id) => id != deviceId).toList();
    // Remove from box
    final index = _box.values.toList().indexOf(deviceId);
    if (index >= 0) _box.deleteAt(index);
  }

  bool isBlocked(String deviceId) => state.contains(deviceId);
}

/// Nearby discovered devices (kept for backward compat)
final nearbyDevicesProvider =
    StateNotifierProvider<NearbyDevicesNotifier, List<DeviceModel>>(
  (ref) => NearbyDevicesNotifier(),
);

class NearbyDevicesNotifier extends StateNotifier<List<DeviceModel>> {
  NearbyDevicesNotifier() : super([]);

  void addDevice(DeviceModel device) {
    state = [...state.where((d) => d.id != device.id), device];
  }

  void removeDevice(String deviceId) {
    state = state.where((d) => d.id != deviceId).toList();
  }

  void clear() {
    state = [];
  }
}
