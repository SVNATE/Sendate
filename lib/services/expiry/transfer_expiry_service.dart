import 'dart:io';

import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';

/// Manages auto-deletion of received files after configured expiry.
class TransferExpiryService {
  static const _expiryBox = 'file_expiry';

  /// Register a received file with expiry
  Future<void> registerFile(String filePath, Duration expiry) async {
    final box = await Hive.openBox(_expiryBox);
    final expiresAt = DateTime.now().add(expiry).toIso8601String();
    await box.put(filePath, expiresAt);
  }

  /// Remove expiry for a file (keep forever)
  Future<void> removeExpiry(String filePath) async {
    final box = await Hive.openBox(_expiryBox);
    await box.delete(filePath);
  }

  /// Check and delete all expired files
  Future<int> cleanupExpired() async {
    final box = await Hive.openBox(_expiryBox);
    final now = DateTime.now();
    var deletedCount = 0;
    final keysToRemove = <String>[];

    for (final key in box.keys) {
      final expiresAtStr = box.get(key) as String?;
      if (expiresAtStr == null) continue;

      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null) continue;

      if (now.isAfter(expiresAt)) {
        // Delete the file
        final file = File(key as String);
        try {
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        } catch (_) {}
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      await box.delete(key);
    }

    return deletedCount;
  }

  /// Get expiry setting from user preferences
  static Duration? getExpiryDuration() {
    final settingsBox = Hive.box(AppConstants.settingsBox);
    final value = settingsBox.get('transfer_expiry', defaultValue: 'never') as String;
    return switch (value) {
      '1hour' => const Duration(hours: 1),
      '1day' => const Duration(days: 1),
      '7days' => const Duration(days: 7),
      '30days' => const Duration(days: 30),
      _ => null, // never
    };
  }

  /// Set the expiry preference
  static Future<void> setExpiryPreference(String value) async {
    final settingsBox = Hive.box(AppConstants.settingsBox);
    await settingsBox.put('transfer_expiry', value);
  }
}
