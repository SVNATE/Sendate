import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nsd/nsd.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';
import '../../shared/models/device_model.dart';
import '../network/network_service.dart';

/// Robust discovery using standard mDNS (Bonjour/ZeroConf) for iOS/Android
/// and fallback UDP Unicast probe for Hotspots.
class DiscoveryService {
  final _log = const AppLogger('Discovery');
  
  // mDNS (nsd)
  Registration? _registration;
  Discovery? _discovery;
  
  // UDP Unicast fallback for hotspots
  RawDatagramSocket? _fallbackSocket;
  Timer? _announceTimer;
  Timer? _cleanupTimer;
  
  final _devicesController = StreamController<List<DeviceModel>>.broadcast();
  final Map<String, _DiscoveredDevice> _discovered = {};
  
  bool _isRunning = false;
  DeviceModel? _localDevice;
  String? _localIp;
  final NetworkService _networkService = NetworkService();
  
  static const _serviceType = '_sendate._tcp';
  static const _staleTimeout = Duration(seconds: 15);
  static const _announceInterval = Duration(seconds: 2);

  Stream<List<DeviceModel>> get devicesStream => _devicesController.stream;
  List<DeviceModel> get currentDevices =>
      _discovered.values.map((d) => d.device).toList();
  bool get isRunning => _isRunning;
  bool hiddenMode = false;

  /// Start discovery
  Future<void> start(DeviceModel localDevice, String? localIp) async {
    if (_isRunning) return;
    _localDevice = localDevice;
    _localIp = localIp;
    _isRunning = true;

    // Get ALL local IPs
    final allIps = await _networkService.getAllLocalIps();
    if (allIps.isNotEmpty && (_localIp == null || _localIp!.isEmpty)) {
      _localIp = allIps.first;
    }

    // Start mDNS Registration and Discovery
    await _startMdns();

    // Bind Fallback UDP Socket for direct gateway probing (Android hotspot case)
    await _bindFallbackSocket();

    // Announce via Fallback immediately, then periodically
    _announceFallback();
    _announceTimer = Timer.periodic(_announceInterval, (_) {
      _announceFallback();
    });

    // Cleanup stale devices every 5s
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _cleanupStale(),
    );
  }

  Future<void> _startMdns() async {
    if (_localDevice == null) return;
    
    // Register service
    try {
      if (!hiddenMode) {
        _registration = await register(Service(
          name: _localDevice!.name,
          type: _serviceType,
          host: _localIp,
          port: AppConstants.transferPort,
          txt: {
            'id': utf8.encode(_localDevice!.id),
            'name': utf8.encode(_localDevice!.name),
            'deviceType': utf8.encode(_localDevice!.deviceType.name),
            'fingerprint': utf8.encode(_localDevice!.fingerprint),
          },
        ));
        _log.info('mDNS service registered: ${_registration?.service.name}');
      }
    } catch (e) {
      _log.debug('mDNS registration failed: $e');
    }

    // Start discovery
    try {
      _discovery = await startDiscovery(
        _serviceType,
        ipLookupType: IpLookupType.v4,
      );
      
      _discovery!.addListener(() {
        for (final service in _discovery!.services) {
          _processMdnsService(service);
        }
      });
      _log.info('mDNS discovery started');
    } catch (e) {
      _log.debug('mDNS discovery failed: $e');
    }
  }

  void _processMdnsService(Service service) {
    if (_localDevice == null || service.txt == null) return;
    
    try {
      final txt = service.txt!;
      final idData = txt['id'];
      if (idData == null) return;
      
      final deviceId = utf8.decode(idData);
      if (deviceId == _localDevice?.id) return;

      final ip = service.host ?? service.addresses?.first.address;
      if (ip == null) return;

      final nameData = txt['name'];
      final deviceTypeData = txt['deviceType'];
      final fingerprintData = txt['fingerprint'];

      final device = DeviceModel(
        id: deviceId,
        name: nameData != null ? utf8.decode(nameData) : (service.name ?? 'Unknown'),
        deviceType: _parseDeviceType(deviceTypeData != null ? utf8.decode(deviceTypeData) : null),
        fingerprint: fingerprintData != null ? utf8.decode(fingerprintData) : '',
        ipAddress: ip,
        port: service.port ?? AppConstants.transferPort,
        connectionType: ConnectionType.wifi,
        lastSeen: DateTime.now(),
      );

      _discovered[deviceId] = _DiscoveredDevice(
        device: device,
        lastSeen: DateTime.now(),
      );
      _devicesController.add(currentDevices);
    } catch (e) {
      _log.debug('Failed to parse mDNS service: $e');
    }
  }

  Future<void> _bindFallbackSocket() async {
    _fallbackSocket?.close();
    try {
      _fallbackSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _fallbackSocket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final dg = _fallbackSocket?.receive();
            if (dg != null) _processDatagram(dg);
          }
        },
        onError: (e) {
          _log.debug('Fallback socket error: $e');
        },
        onDone: () {
          _log.debug('Fallback socket closed');
        },
      );
    } catch (e) {
      _log.debug('Fallback socket bind failed: $e');
    }
  }

  /// Stop discovery
  Future<void> stop() async {
    _isRunning = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    
    if (_registration != null) {
      try { await unregister(_registration!); } catch (_) {}
      _registration = null;
    }
    
    if (_discovery != null) {
      try { await stopDiscovery(_discovery!); } catch (_) {}
      _discovery = null;
    }
    
    _fallbackSocket?.close();
    _fallbackSocket = null;
    
    _discovered.clear();
    _devicesController.add([]);
  }

  /// Restart discovery sockets when network interface changes.
  Future<void> restartSockets() async {
    if (!_isRunning) return;
    _log.info('Network change detected — rebinding discovery sockets');
    
    await stop();
    _isRunning = true;
    await _startMdns();
    await _bindFallbackSocket();
    
    // Burst announce
    for (var i = 0; i < 3; i++) {
      _announceFallback();
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Force re-announce
  Future<void> reannounce() async {
    final allIps = await _networkService.getAllLocalIps();
    if (allIps.isNotEmpty) {
      _localIp = allIps.first;
    }
    
    for (var i = 0; i < 3; i++) {
      _announceFallback();
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  void _announceFallback() {
    if (_localDevice == null || hiddenMode) return;

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

    // Use an ephemeral socket for sending to prevent async OS errors (like 'No route to host')
    // from crashing the main listening socket stream.
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      socket.broadcastEnabled = true;

      void sendTo(String ip) {
        try {
          socket.send(data, InternetAddress(ip), AppConstants.discoveryPort);
        } catch (_) {}
      }

      // Direct gateway probe (for Hotspot)
      _networkService.getGatewayIp().then((gw) {
        if (gw != null) sendTo(gw);
      });

      // Probe common hardcoded gateways and hotspot clients
      for (final gwIp in [
        '192.168.43.1', '192.168.49.1', '172.20.10.1', 
        '192.168.43.100', '192.168.49.100', '172.20.10.2',
        '255.255.255.255'
      ]) {
        sendTo(gwIp);
      }

      // Close the ephemeral socket after allowing time for sends to flush
      Future.delayed(const Duration(milliseconds: 500), () => socket.close());
    }).catchError((_) {});
  }

  void _processDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json['type'] != 'announce') return;

      final deviceId = json['id'] as String;
      if (deviceId == _localDevice?.id) return;

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
      _log.debug('Fallback datagram processing failed: $e');
    }
  }

  void _cleanupStale() {
    final now = DateTime.now();
    final before = _discovered.length;

    // Get all device IDs currently active in mDNS
    final mdnsActiveIds = <String>{};
    if (_discovery != null) {
      for (final s in _discovery!.services) {
        if (s.txt != null && s.txt!['id'] != null) {
          try {
            mdnsActiveIds.add(utf8.decode(s.txt!['id']!));
          } catch (_) {}
        }
      }
    }

    _discovered.removeWhere((id, d) {
      // If it's still active via mDNS, don't remove it, and refresh its lastSeen
      if (mdnsActiveIds.contains(id)) {
        d.lastSeen = now;
        return false;
      }
      return now.difference(d.lastSeen) > _staleTimeout;
    });

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
  DateTime lastSeen;

  _DiscoveredDevice({required this.device, required this.lastSeen});
}
