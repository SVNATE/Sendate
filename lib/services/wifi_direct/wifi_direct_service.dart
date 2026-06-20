import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';

/// WiFi Direct (P2P) service for direct device-to-device connections
/// without a shared router or hotspot.
class WifiDirectService {
  static const _channel = MethodChannel('com.svnate.sendate/wifi_direct');
  final _log = const AppLogger('WifiDirect');
  final _peersController = StreamController<List<DeviceModel>>.broadcast();
  final Map<String, DeviceModel> _peers = {};
  bool _isDiscovering = false;
  String? _groupOwnerIp;

  Stream<List<DeviceModel>> get peersStream => _peersController.stream;
  List<DeviceModel> get currentPeers => _peers.values.toList();
  bool get isDiscovering => _isDiscovering;
  String? get groupOwnerIp => _groupOwnerIp;

  /// Initialize WiFi Direct
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      _log.debug('isAvailable check failed: $e');
      return false;
    }
  }

  /// Start discovering WiFi Direct peers
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _peers.clear();

    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      await _channel.invokeMethod('startDiscovery');
    } catch (e) {
      _isDiscovering = false;
    }
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    try {
      await _channel.invokeMethod('stopDiscovery');
    } catch (e) {
      _log.debug('stopDiscovery failed: $e');
    }
  }

  /// Connect to a WiFi Direct peer
  Future<bool> connect(String deviceAddress) async {
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'address': deviceAddress,
      });
      return result ?? false;
    } catch (e) {
      _log.debug('connect to $deviceAddress failed: $e');
      return false;
    }
  }

  /// Disconnect from WiFi Direct group
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      _groupOwnerIp = null;
    } catch (e) {
      _log.debug('disconnect failed: $e');
    }
  }

  /// Request current group info and update [groupOwnerIp].
  /// Call this after [connect] / [onConnected] fires to obtain the IP of the
  /// group owner — the non-owner device needs this IP to open a TCP connection.
  Future<String?> requestGroupInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getGroupInfo');
      if (result != null) {
        _groupOwnerIp = result['groupOwnerAddress'] as String?;
        _log.debug('Group owner IP: $_groupOwnerIp');
      }
      return _groupOwnerIp;
    } catch (e) {
      _log.debug('getGroupInfo failed: $e');
      return null;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPeersFound':
        final peers = (call.arguments as List?)?.cast<Map>() ?? [];
        _peers.clear();
        for (final peer in peers) {
          final map = Map<String, dynamic>.from(peer);
          final device = DeviceModel(
            id: 'wfd-${map['address']}',
            name: map['name'] as String? ?? 'WiFi Direct Device',
            deviceType: DeviceType.unknown,
            fingerprint: map['address'] as String? ?? '',
            connectionType: ConnectionType.wifiDirect,
            lastSeen: DateTime.now(),
          );
          _peers[device.id] = device;
        }
        _peersController.add(currentPeers);
      case 'onConnected':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _groupOwnerIp = args['groupOwnerAddress'] as String?;
        // Auto-fetch accurate IP via getGroupInfo (broadcasts can carry stale address)
        Future.delayed(const Duration(seconds: 1), requestGroupInfo);
      case 'onDisconnected':
        _groupOwnerIp = null;
    }
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await _peersController.close();
  }
}
