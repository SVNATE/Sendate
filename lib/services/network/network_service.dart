import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Provides local network information with hotspot detection.
class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  /// Get the local IP address — handles both client and hotspot (AP) mode.
  Future<String?> getLocalIp() async {
    // Strategy 1: network_info_plus (works when device is WiFi CLIENT)
    try {
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0') {
        return wifiIP;
      }
    } catch (_) {}

    // Strategy 2: Enumerate all interfaces
    // This catches the hotspot interface (wlan0/ap0 on Android when device IS the AP)
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      String? hotspotIp;
      String? regularIp;

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          final name = iface.name.toLowerCase();

          // Hotspot interfaces are typically: swlan0, ap0, wlan1, or have .43./.49./.10. subnet
          if (name.contains('ap') ||
              name == 'swlan0' ||
              name == 'wlan1' ||
              ip.startsWith('192.168.43.') ||
              ip.startsWith('192.168.49.') ||
              ip.startsWith('172.20.10.')) {
            hotspotIp = ip;
          } else {
            regularIp = ip;
          }
        }
      }

      // Prefer hotspot IP if we're running as AP, otherwise use regular
      return hotspotIp ?? regularIp;
    } catch (_) {}

    return null;
  }

  /// Get ALL local IPs (covers both WiFi client and hotspot AP interfaces)
  Future<List<String>> getAllLocalIps() async {
    final ips = <String>[];
    try {
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && wifiIP != '0.0.0.0') {
        ips.add(wifiIP);
      }
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}

    return ips;
  }

  /// Get the gateway IP of the current network (uses system routing info)
  Future<String?> getGatewayIp() async {
    // Strategy 1: Use route command (macOS/Linux)
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('route', ['get', 'default']);
        final output = result.stdout as String;
        for (final line in output.split('\n')) {
          if (line.contains('gateway')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final gw = parts.last;
              if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(gw)) return gw;
            }
          }
        }
      }
    } catch (_) {}

    // Strategy 2: Use ip route (Linux)
    try {
      if (Platform.isLinux) {
        final result = await Process.run('ip', ['route', 'show', 'default']);
        final match = RegExp(r'via (\d+\.\d+\.\d+\.\d+)').firstMatch(result.stdout as String);
        if (match != null) return match.group(1);
      }
    } catch (_) {}

    // Strategy 3: Fallback — derive from local IP (assume .1)
    final ip = await getLocalIp();
    if (ip == null) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  }

  Future<String?> getWifiName() async {
    try {
      return await _networkInfo.getWifiName();
    } catch (_) {
      return null;
    }
  }

  Future<String?> getSubnet() async {
    final ip = await getLocalIp();
    if (ip == null) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  /// Detect if the device is likely running a hotspot (is the AP)
  Future<bool> isHotspotHost() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('ap') || name == 'swlan0' || name == 'wlan1') {
          return true;
        }
        for (final addr in iface.addresses) {
          // Hotspot hosts have .1 as last octet typically
          if ((addr.address.startsWith('192.168.43.') ||
               addr.address.startsWith('192.168.49.') ||
               addr.address.startsWith('172.20.10.')) &&
              addr.address.endsWith('.1')) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Detect if device is a hotspot CLIENT (connected to someone else's hotspot)
  Future<bool> isHotspotClient() async {
    final ip = await getLocalIp();
    if (ip == null) return false;
    return (ip.startsWith('192.168.43.') ||
            ip.startsWith('192.168.49.') ||
            ip.startsWith('172.20.10.')) &&
        !ip.endsWith('.1');
  }

  Future<String?> getSubnetBroadcast() async {
    final ip = await getLocalIp();
    if (ip == null) return null;
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  Future<List<NetworkInterfaceInfo>> getInterfaces() async {
    final result = <NetworkInterfaceInfo>[];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            result.add(NetworkInterfaceInfo(
              name: iface.name,
              ip: addr.address,
              isHotspot: addr.address.startsWith('192.168.43.') ||
                  addr.address.startsWith('192.168.49.') ||
                  addr.address.startsWith('172.20.10.'),
            ));
          }
        }
      }
    } catch (_) {}
    return result;
  }
}

class NetworkInterfaceInfo {
  final String name;
  final String ip;
  final bool isHotspot;

  NetworkInterfaceInfo({required this.name, required this.ip, required this.isHotspot});
}
