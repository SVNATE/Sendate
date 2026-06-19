import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';

/// Bluetooth device discovery and connection service.
/// Uses platform channels for Bluetooth Classic scanning.
class BluetoothService {
  static const _channel = MethodChannel('com.svnate.sendate/bluetooth');
  final _log = const AppLogger('Bluetooth');
  final _devicesController = StreamController<List<DeviceModel>>.broadcast();
  final Map<String, DeviceModel> _discovered = {};
  bool _isScanning = false;

  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;
  List<DeviceModel> get currentDevices => _discovered.values.toList();
  bool get isScanning => _isScanning;

  /// Check if Bluetooth is available and enabled
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      _log.debug('isAvailable check failed: $e');
      return false;
    }
  }

  /// Start scanning for Bluetooth devices
  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    _discovered.clear();

    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      await _channel.invokeMethod('startScan');
    } catch (e) {
      _isScanning = false;
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    _isScanning = false;
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      _log.debug('stopScan failed: $e');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onDeviceFound') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final device = DeviceModel(
        id: 'bt-${args['address']}',
        name: args['name'] as String? ?? args['address'] as String,
        deviceType: DeviceType.unknown,
        fingerprint: args['address'] as String? ?? '',
        connectionType: ConnectionType.bluetooth,
        lastSeen: DateTime.now(),
      );

      _discovered[device.id] = device;
      _devicesController.add(currentDevices);
    } else if (call.method == 'onScanFinished') {
      _isScanning = false;
    }
  }

  Future<void> dispose() async {
    await stopScan();
    await _devicesController.close();
  }
}
