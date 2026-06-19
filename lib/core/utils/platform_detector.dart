import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detects if the device is a TV form factor.
class PlatformDetector {
  static bool? _isTV;

  static Future<bool> isTV() async {
    if (_isTV != null) return _isTV!;

    if (!Platform.isAndroid) {
      _isTV = false;
      return false;
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      // Check system features for leanback (TV indicator)
      final features = info.systemFeatures;
      _isTV = features.contains('android.software.leanback') ||
          features.contains('android.hardware.type.television');
    } catch (e) {
      debugPrint('[PlatformDetector] TV detection failed: $e');
      _isTV = false;
    }

    return _isTV!;
  }
}
