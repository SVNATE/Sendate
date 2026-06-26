import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../network/network_service.dart';

/// Robust UDP discovery with multiple fallback strategies:
/// 1. Subnet broadcast (192.168.x.255)
/// 2. Global broadcast (255.255.255.255)
/// 3. Multicast group (224.0.0.167)
/// 4. Multiple interface scanning
class DiscoveryService {
  final _log = const AppLogger('Discovery');
  RawDatagramSocket? _broadcastSocket;
  RawDatagramSocket? _multicastSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  final _devicesController = StreamController<List<DeviceModel>>.broadcast();
  final Map<String, _DiscoveredDevice> _discovered = {};
  bool _isRunning = false;
  bool _isBinding = false;
  DeviceModel? _localDevice;
  String? _localIp;
  final NetworkService _networkService = NetworkService();

  static const _multicastGroup = '224.0.0.167';
  static const _staleTimeout = Duration(seconds: 15);
  static const _announceInterval = Duration(seconds: 1);

  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;
  List<DeviceModel> get currentDevices =>
      _discovered.values.map((d) => d.device).toList();
  bool get isRunning => _isRunning;

  /// Start discovery — announce on multiple channels and listen
  Future<void> start(DeviceModel localDevice, String? localIp) async {
    if (_isRunning) return;
    _localDevice = localDevice;
    _localIp = localIp;
    _isRunning = true;

    // Get ALL local IPs (covers hotspot + wifi client interfaces)
    final allIps = await _networkService.getAllLocalIps();
    if (allIps.isNotEmpty && (_localIp == null || _localIp!.isEmpty)) {
      _localIp = allIps.first;
    }

    await _bindSockets();

    // Announce immediately, then every 1 second
    _announce();
    _announceTimer = Timer.periodic(_announceInterval, (_) => _announce());

    // Cleanup stale devices every 5s
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _cleanupStale(),
    );

    // Gateway probe: try to directly contact the gateway (for hotspot client scenario)
    _probeGateway();
  }

  Future<void> _bindSockets() async {
    if (_isBinding) return;
    _isBinding = true;
    
    // Close existing sockets before rebinding
    _broadcastSocket?.close();
    _broadcastSocket = null;
    try { _multicastSocket?.leaveMulticast(InternetAddress(_multicastGroup)); } catch (_) {}
    _multicastSocket?.close();
    _multicastSocket = null;

    // Bind broadcast socket
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        _broadcastSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          AppConstants.discoveryPort,
          reuseAddress: true,
          reusePort: true,
        );
        _broadcastSocket!.broadcastEnabled = true;
        _broadcastSocket!.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _broadcastSocket?.receive();
            if (dg != null) _processDatagram(dg);
          }
        });
        break;
      } catch (e) {
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }

    // Bind multicast socket for fallback
    try {
      _multicastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort + 1,
        reuseAddress: true,
        reusePort: true,
      );
      _multicastSocket!.joinMulticast(InternetAddress(_multicastGroup));
      _multicastSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _multicastSocket?.receive();
          if (dg != null) _processDatagram(dg);
        }
      });
    } catch (e) {
      _log.debug('Multicast socket bind failed: $e');
    }
    _isBinding = false;
  }

  /// Stop discovery
  Future<void> stop() async {
    _isRunning = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    try {
      _multicastSocket?.leaveMulticast(InternetAddress(_multicastGroup));
    } catch (e) {
      _log.debug('Multicast leave failed: $e');
    }
    _multicastSocket?.close();
    _multicastSocket = null;
    _discovered.clear();
    _devicesController.add([]);
  }

  /// Restart discovery sockets when network interface changes (WiFi switch, hotspot toggle).
  /// Called by ConnectivityMonitor when network state changes.
  Future<void> restartSockets() async {
    if (!_isRunning) return;
    _log.info('Network change detected — rebinding discovery sockets');
    await _bindSockets();
    // Burst announce to quickly re-discover devices on new network
    for (var i = 0; i < 5; i++) {
      _announce();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _probeGateway();
  }

  /// Force re-announce (call on app resume or network change)
  Future<void> reannounce() async {
    // Refresh IP from ALL interfaces
    final allIps = await _networkService.getAllLocalIps();
    if (allIps.isNotEmpty) {
      _localIp = allIps.first;
    }
    // Burst announce 3 times
    for (var i = 0; i < 3; i++) {
      _announce();
      await Future.delayed(const Duration(milliseconds: 200));
    }
    // Probe gateway again
    _probeGateway();
  }

  /// If true, device will not announce itself (hidden mode)
  bool hiddenMode = false;

  void _announce() {
    if (_localDevice == null) return;
    if (hiddenMode) return;

    final packet = jsonEncode({
      'type': 'announce',
      'id': _localDevice!.id,
      'name': _localDevice!.name,
      'deviceType': _localDevice!.deviceType.name,
      'fingerprint': _localDevice!.fingerprint,
      'ip': _localIp ?? '',
      'port': AppConstants.transferPort,
      'version': AppConstants.appVersion,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    final data = utf8.encode(packet);

    // Get all local IPs and broadcast from each subnet
    _networkService.getAllLocalIps().then((allIps) {
      for (final ip in allIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          try {
            _broadcastSocket?.send(data, InternetAddress(subnetBroadcast), AppConstants.discoveryPort);
          } catch (e) {
            _log.debug('Subnet broadcast send failed ($subnetBroadcast): $e');
          }
        }
      }
    });

    // Global broadcast
    if (_broadcastSocket != null) {
      try {
        _broadcastSocket!.send(data, InternetAddress('255.255.255.255'), AppConstants.discoveryPort);
      } catch (e) {
        _log.debug('Global broadcast send failed: $e');
      }
    }

    // Multicast
    if (_multicastSocket != null) {
      try {
        _multicastSocket!.send(data, InternetAddress(_multicastGroup), AppConstants.discoveryPort + 1);
      } catch (e) {
        _log.debug('Multicast send failed: $e');
      }
    }

    // Common hotspot subnets (cover all Android hotspot variants)
    if (_broadcastSocket != null) {
      for (final subnet in [
        '192.168.43.255', '192.168.49.255', '172.20.10.255',
        '192.168.0.255', '192.168.1.255', '192.168.2.255',
        '10.47.140.255', '10.0.0.255', '10.42.0.255',
      ]) {
        try {
          _broadcastSocket!.send(data, InternetAddress(subnet), AppConstants.discoveryPort);
        } catch (e) {
          _log.debug('Hotspot subnet broadcast failed ($subnet): $e');
        }
      }
    }

    // CRITICAL: Also send unicast directly to the gateway (hotspot host)
    _networkService.getGatewayIp().then((gw) {
      if (gw != null && _broadcastSocket != null) {
        try {
          _broadcastSocket!.send(data, InternetAddress(gw), AppConstants.discoveryPort);
        } catch (e) {
          _log.debug('Gateway unicast send failed ($gw): $e');
        }
      }
    });

    // FULL PROOF iOS FIX: Unicast Subnet Sweep
    // Since Apple strictly blocks raw Multicast/Broadcast on iOS 14+ without special entitlements,
    // we bypass this by firing UDP Unicast to every single IP in the subnet. Unicast is ALLOWED!
    if (_localIp != null && _localIp!.isNotEmpty && _broadcastSocket != null) {
      final parts = _localIp!.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (int i = 1; i < 255; i++) {
          final targetIp = '$prefix.$i';
          if (targetIp == _localIp) continue;
          try {
            _broadcastSocket!.send(data, InternetAddress(targetIp), AppConstants.discoveryPort);
          } catch (_) {
            // Ignore errors for individual IPs
          }
        }
      }
    }
  }

  /// Probe the gateway IP directly with a TCP connection.
  /// Probe the gateway directly with UDP unicast.
  /// KEY FIX: On hotspot networks, the gateway IS the other Sendate device.
  /// Unicast always works even when broadcast doesn't.
  Future<void> _probeGateway() async {
    try {
      final gatewayIp = await _networkService.getGatewayIp();
      if (gatewayIp != null && _localDevice != null) {
        // Send announce packet directly to the gateway IP via unicast UDP
        _probeDirectIp(gatewayIp);
      }
    } catch (e) {
      _log.debug('Gateway probe failed: $e');
    }

    // Also probe common hardcoded gateways and hotspot clients as fallback
    for (final gwIp in [
      '192.168.43.1', '192.168.49.1', '172.20.10.1', // Hotspot Hosts
      '192.168.43.100', '192.168.49.100', '172.20.10.2' // Hotspot Clients
    ]) {
      _probeDirectIp(gwIp);
    }
  }

  /// Directly probe a specific IP to check if Sendate is running there
  Future<void> _probeDirectIp(String ip) async {
    if (_broadcastSocket == null || _localDevice == null) return;

    final packet = jsonEncode({
      'type': 'announce',
      'id': _localDevice!.id,
      'name': _localDevice!.name,
      'deviceType': _localDevice!.deviceType.name,
      'fingerprint': _localDevice!.fingerprint,
      'ip': _localIp ?? '',
      'port': AppConstants.transferPort,
      'version': AppConstants.appVersion,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });

    try {
      _broadcastSocket!.send(utf8.encode(packet), InternetAddress(ip), AppConstants.discoveryPort);
    } catch (e) {
      _log.debug('Direct probe send failed ($ip): $e');
    }
  }

  void _processDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json['type'] != 'announce') return;

      final deviceId = json['id'] as String;
      if (deviceId == _localDevice?.id) return; // Ignore self

      final ip = (json['ip'] as String?)?.isNotEmpty == true
          ? json['ip'] as String
          : datagram.address.address;

      final device = DeviceModel(
        id: deviceId,
        name: json['name'] as String? ?? 'Unknown',
        deviceType: _parseDeviceType(json['deviceType'] as String?),
        fingerprint: json['fingerprint'] as String? ?? '',
        ipAddress: ip,
        port: json['port'] as int? ?? AppConstants.transferPort,
        connectionType: ConnectionType.wifi,
        lastSeen: DateTime.now(),
      );

      _discovered[deviceId] = _DiscoveredDevice(
        device: device,
        lastSeen: DateTime.now(),
      );

      _devicesController.add(currentDevices);
    } catch (e) {
      _log.debug('Datagram processing failed: $e');
    }
  }

  void _cleanupStale() {
    final now = DateTime.now();
    final before = _discovered.length;
    _discovered.removeWhere((_, d) => now.difference(d.lastSeen) > _staleTimeout);
    if (_discovered.length != before) {
      _devicesController.add(currentDevices);
    }
  }

  DeviceType _parseDeviceType(String? type) => switch (type) {
        'phone' => DeviceType.phone,
        'tablet' => DeviceType.tablet,
        'laptop' => DeviceType.laptop,
        'desktop' => DeviceType.desktop,
        'tv' => DeviceType.tv,
        _ => DeviceType.unknown,
      };

  Future<void> dispose() async {
    await stop();
    await _devicesController.close();
  }
}

class _DiscoveredDevice {
  final DeviceModel device;
  final DateTime lastSeen;

  _DiscoveredDevice({required this.device, required this.lastSeen});
}
