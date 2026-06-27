import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';

/// Theme mode provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_loadThemeMode());

  static ThemeMode _loadThemeMode() {
    final box = Hive.box(AppConstants.settingsBox);
    final value = box.get('theme_mode', defaultValue: 'system') as String;
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final box = Hive.box(AppConstants.settingsBox);
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await box.put('theme_mode', value);
  }
}

/// Device name provider
final deviceNameProvider = StateNotifierProvider<DeviceNameNotifier, String>(
  (ref) => DeviceNameNotifier(),
);

class DeviceNameNotifier extends StateNotifier<String> {
  DeviceNameNotifier() : super(_loadDeviceName());

  static String _loadDeviceName() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('device_name', defaultValue: 'My Device') as String;
  }

  Future<void> setDeviceName(String name) async {
    state = name;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('device_name', name);
  }
}

/// Save location provider
final saveLocationProvider = StateNotifierProvider<SaveLocationNotifier, String>(
  (ref) => SaveLocationNotifier(),
);

class SaveLocationNotifier extends StateNotifier<String> {
  SaveLocationNotifier() : super(_loadSaveLocation());

  static String _loadSaveLocation() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('save_location', defaultValue: 'Downloads') as String;
  }

  Future<void> setSaveLocation(String path) async {
    state = path;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('save_location', path);
  }
}

/// Auto-convert toggle
final autoConvertProvider = StateNotifierProvider<AutoConvertNotifier, bool>(
  (ref) => AutoConvertNotifier(),
);

class AutoConvertNotifier extends StateNotifier<bool> {
  AutoConvertNotifier() : super(_load());

  static bool _load() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('auto_convert', defaultValue: true) as bool;
  }

  Future<void> toggle() async {
    state = !state;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('auto_convert', state);
  }
}

/// Auto-accept all incoming transfers without prompting
final autoAcceptProvider = StateNotifierProvider<AutoAcceptNotifier, bool>(
  (ref) => AutoAcceptNotifier(),
);

class AutoAcceptNotifier extends StateNotifier<bool> {
  AutoAcceptNotifier() : super(_load());

  static bool _load() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('auto_accept_all', defaultValue: false) as bool;
  }

  Future<void> toggle() async {
    state = !state;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('auto_accept_all', state);
  }
}

/// Hidden Mode toggle — device stops announcing itself for discovery.
/// Backend (discoveryService.hiddenMode) is set from main.dart on state change.
final hiddenModeProvider = StateNotifierProvider<HiddenModeNotifier, bool>(
  (ref) => HiddenModeNotifier(),
);

class HiddenModeNotifier extends StateNotifier<bool> {
  HiddenModeNotifier() : super(_load());

  static bool _load() {
    final box = Hive.box(AppConstants.settingsBox);
    return box.get('hidden_mode', defaultValue: false) as bool;
  }

  Future<void> toggle() async {
    state = !state;
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('hidden_mode', state);
  }
}

/// Transfer expiry duration provider — determines how long received files are kept.
/// null = keep forever.
final transferExpiryProvider =
    StateNotifierProvider<TransferExpiryNotifier, Duration?>(
  (ref) => TransferExpiryNotifier(),
);

class TransferExpiryNotifier extends StateNotifier<Duration?> {
  TransferExpiryNotifier() : super(_load());

  static Duration? _load() {
    final box = Hive.box(AppConstants.settingsBox);
    final hours = box.get('transfer_expiry_hours') as int?;
    return hours == null ? null : Duration(hours: hours);
  }

  Future<void> setExpiry(Duration? expiry) async {
    state = expiry;
    final box = Hive.box(AppConstants.settingsBox);
    if (expiry == null) {
      await box.delete('transfer_expiry_hours');
    } else {
      await box.put('transfer_expiry_hours', expiry.inHours);
    }
  }
}
