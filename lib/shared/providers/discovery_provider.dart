import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/bluetooth/bluetooth_service.dart';
import '../../services/discovery/discovery_service.dart';
import '../../services/network/network_service.dart';
import '../../services/wifi_direct/wifi_direct_service.dart';
import '../models/device_model.dart';
import 'device_provider.dart';

/// Discovery service singleton
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Network service singleton
final networkServiceProvider = Provider<NetworkService>((ref) {
  return NetworkService();
});

/// Bluetooth service singleton
final bluetoothServiceProvider = Provider<BluetoothService>((ref) {
  final service = BluetoothService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// WiFi Direct service singleton
final wifiDirectServiceProvider = Provider<WifiDirectService>((ref) {
  final service = WifiDirectService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Whether discovery is currently active
final discoveryActiveProvider = StateProvider<bool>((ref) => false);

/// Whether Bluetooth scan is active
final bluetoothActiveProvider = StateProvider<bool>((ref) => false);

/// WiFi discovered devices stream
final nearbyDevicesStreamProvider = StreamProvider<List<DeviceModel>>((ref) {
  final service = ref.watch(discoveryServiceProvider);
  return service.devicesStream;
});

/// Bluetooth discovered devices stream
final bluetoothDevicesStreamProvider = StreamProvider<List<DeviceModel>>((ref) {
  final service = ref.watch(bluetoothServiceProvider);
  return service.devicesStream;
});

/// WiFi Direct discovered peers stream
final wifiDirectDevicesStreamProvider = StreamProvider<List<DeviceModel>>((ref) {
  final service = ref.watch(wifiDirectServiceProvider);
  return service.peersStream;
});

/// Combined: all nearby devices (WiFi + Bluetooth + WiFi Direct + manual)
final allNearbyDevicesProvider = Provider<List<DeviceModel>>((ref) {
  final wifiDevices = ref.watch(nearbyDevicesStreamProvider).valueOrNull ?? [];
  final btDevices = ref.watch(bluetoothDevicesStreamProvider).valueOrNull ?? [];
  final wfdDevices = ref.watch(wifiDirectDevicesStreamProvider).valueOrNull ?? [];
  final manualDevices = ref.watch(nearbyDevicesProvider);

  // Merge all, deduplicate by ID
  final map = <String, DeviceModel>{};
  for (final d in wifiDevices) {
    map[d.id] = d;
  }
  for (final d in btDevices) {
    map[d.id] = d;
  }
  for (final d in wfdDevices) {
    map[d.id] = d;
  }
  for (final d in manualDevices) {
    map[d.id] = d;
  }
  return map.values.toList();
});

/// Controller to start/stop discovery
final discoveryControllerProvider = Provider<DiscoveryController>((ref) {
  return DiscoveryController(ref);
});

class DiscoveryController {
  final Ref _ref;

  DiscoveryController(this._ref);

  Future<void> startDiscovery() async {
    final service = _ref.read(discoveryServiceProvider);
    final networkService = _ref.read(networkServiceProvider);
    final device = _ref.read(currentDeviceProvider);

    if (device == null || service.isRunning) return;

    final ip = await networkService.getLocalIp();
    await service.start(device, ip);
    _ref.read(discoveryActiveProvider.notifier).state = true;
  }

  Future<void> stopDiscovery() async {
    final service = _ref.read(discoveryServiceProvider);
    await service.stop();
    _ref.read(discoveryActiveProvider.notifier).state = false;
  }

  Future<void> restartDiscovery() async {
    await stopDiscovery();
    await Future.delayed(const Duration(milliseconds: 300));
    await startDiscovery();
    // Also trigger re-announce burst
    _ref.read(discoveryServiceProvider).reannounce();
  }

  /// Start Bluetooth scanning
  Future<void> startBluetoothScan() async {
    // Request permissions first (Android 12+)
    await _requestBluetoothPermissions();

    final btService = _ref.read(bluetoothServiceProvider);
    final available = await btService.isAvailable();
    if (!available) return;

    await btService.startScan();
    _ref.read(bluetoothActiveProvider.notifier).state = true;

    // Auto-stop after 12 seconds
    Future.delayed(const Duration(seconds: 12), () {
      btService.stopScan();
      _ref.read(bluetoothActiveProvider.notifier).state = false;
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {}
  }

  /// Stop Bluetooth scanning
  Future<void> stopBluetoothScan() async {
    final btService = _ref.read(bluetoothServiceProvider);
    await btService.stopScan();
    _ref.read(bluetoothActiveProvider.notifier).state = false;
  }

  /// Start all discovery methods
  Future<void> startAll() async {
    await startDiscovery();
    await startBluetoothScan();
    await startWifiDirectDiscovery();
  }

  /// Start WiFi Direct peer discovery
  Future<void> startWifiDirectDiscovery() async {
    final wfdService = _ref.read(wifiDirectServiceProvider);
    final available = await wfdService.isAvailable();
    if (!available) return;
    await wfdService.startDiscovery();
  }
}
