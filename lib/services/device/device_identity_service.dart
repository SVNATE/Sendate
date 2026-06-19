import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/device_model.dart';

/// Generates and manages local device identity.
class DeviceIdentityService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<DeviceModel> getDeviceIdentity({
    required String? storedId,
    required String? storedName,
  }) async {
    final id = storedId ?? const Uuid().v4();
    final name = storedName ?? await _getDefaultDeviceName();
    final deviceType = _detectDeviceType();
    final fingerprint = _generateFingerprint(id);

    return DeviceModel(
      id: id,
      name: name,
      deviceType: deviceType,
      fingerprint: fingerprint,
    );
  }

  Future<String> _getDefaultDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.model;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.name;
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return info.computerName;
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return info.computerName;
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return info.prettyName;
      }
    } catch (_) {}
    return 'My Device';
  }

  DeviceType _detectDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) return DeviceType.phone;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return DeviceType.laptop;
    }
    return DeviceType.unknown;
  }

  String _generateFingerprint(String id) {
    // Simple fingerprint from device ID — first 12 chars in pairs
    final hash = id.replaceAll('-', '').substring(0, 12).toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < hash.length; i += 2) {
      if (i > 0) buffer.write(':');
      buffer.write(hash.substring(i, i + 2));
    }
    return buffer.toString();
  }
}
