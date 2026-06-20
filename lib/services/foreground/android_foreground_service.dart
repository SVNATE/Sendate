import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter-side controller for the Android foreground service.
/// The service runs its own FlutterEngine (background_main.dart) for discovery/clipboard.
/// This class is used by the MAIN UI engine to communicate with the service.
///
/// - Persistent notification with connected device info
/// - "Send Clipboard" and "Send Files" action buttons
/// - Keeps running even when app is swiped from recents
/// - Auto-starts on boot
class AndroidForegroundService {
  static const _channel = MethodChannel('com.svnate.sendate/foreground_service');
  static AndroidForegroundService? _instance;

  /// Callback when "Send Clipboard" is tapped (forwarded from service)
  VoidCallback? _onSendClipboardAction;

  /// Clipboard text pre-read in native onNewIntent (avoids Android 10+ focus race)
  String? _pendingClipboardText;

  set onSendClipboardAction(VoidCallback? cb) {
    _onSendClipboardAction = cb;
    // Replay any queued action
    if (cb != null && _pendingAction == 'send_clipboard') {
      _pendingAction = null;
      cb();
    }
  }

  /// Callback when "Send Files" (pick_files) is triggered from notification
  VoidCallback? _onSendFilesAction;
  set onSendFilesAction(VoidCallback? cb) {
    _onSendFilesAction = cb;
    // Replay any queued action
    if (cb != null && (_pendingAction == 'send_files' || _pendingAction == 'pick_files')) {
      _pendingAction = null;
      cb();
    }
  }

  /// Stores action if received before callbacks are wired
  String? _pendingAction;

  AndroidForegroundService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static AndroidForegroundService get instance {
    _instance ??= AndroidForegroundService._();
    return _instance!;
  }

  /// Whether this service is applicable (Android only)
  static bool get isSupported => Platform.isAndroid;

  /// Start the foreground service
  Future<bool> start() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('startService');
      debugPrint('[ForegroundService] Started: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundService] Start error: $e');
      return false;
    }
  }

  /// Stop the foreground service
  Future<bool> stop() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('stopService');
      debugPrint('[ForegroundService] Stopped: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ForegroundService] Stop error: $e');
      return false;
    }
  }

  /// Check if the service is running
  Future<bool> get isRunning async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check for pending notification action (e.g., "pick_files" when activity relaunched)
  Future<void> checkPendingAction() async {
    if (!isSupported) return;
    try {
      final action = await _channel.invokeMethod<String>('getPendingAction');
      if (action != null && action.isNotEmpty) {
        debugPrint('[ForegroundService] Pending action: $action');
        _executeAction(action);
      }
    } catch (e) {
      debugPrint('[ForegroundService] getPendingAction error: $e');
    }
  }

  /// Update the clipboard auto-sync state in the background engine.
  /// Called when the user toggles the setting in the main UI.
  Future<void> updateClipboardAutoSync(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('updateClipboardAutoSync', enabled);
      debugPrint('[ForegroundService] Forwarded updateClipboardAutoSync=$enabled to background engine');
    } catch (e) {
      debugPrint('[ForegroundService] updateClipboardAutoSync error: $e');
    }
  }

  /// Update notification directly from the UI (supplementary to background engine's updates)
  Future<void> updateConnectedDevices(List<String> deviceNames) async {
    if (!isSupported) return;
    try {
      // Send device names to the native service to update the foreground notification
      // This bridges the gap between UI discovery and the background engine's discovery
      await _channel.invokeMethod('updateNotification', {
        'title': 'Sendate',
        'body': deviceNames.isEmpty
            ? 'Searching for devices...'
            : deviceNames.length == 1
                ? 'Connected to: ${deviceNames.first}'
                : 'Connected to ${deviceNames.length} devices',
        'devices': deviceNames,
      });
    } catch (e) {
      debugPrint('[ForegroundService] updateConnectedDevices error: $e');
    }
  }

  /// Pop the clipboard text pre-read in Kotlin's onNewIntent.
  /// Returns null and clears after first read.
  String? popPendingClipboardText() {
    final text = _pendingClipboardText;
    _pendingClipboardText = null;
    return text;
  }

  /// Handle callbacks from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationAction':
        final action = call.arguments as String? ?? '';
        debugPrint('[ForegroundService] Notification action received: $action');
        _executeAction(action);
        break;
      case 'onSendClipboardFromNotification':
        // Native onNewIntent pre-read the clipboard to avoid Android 10+ focus race.
        // Store the text so the callback can use it without calling getClipboard() again.
        final clipText = call.arguments as String? ?? '';
        debugPrint('[ForegroundService] onSendClipboardFromNotification: ${clipText.length} chars');
        _pendingClipboardText = clipText.isNotEmpty ? clipText : null;
        _executeAction('send_clipboard');
        break;
      case 'onSendClipboard':
        debugPrint('[ForegroundService] Send Clipboard from notification');
        _executeAction('send_clipboard');
        break;
      case 'onSendFiles':
        debugPrint('[ForegroundService] Send Files from notification');
        _executeAction('pick_files');
        break;
    }
  }

  void _executeAction(String action) {
    switch (action) {
      case 'send_clipboard':
        if (_onSendClipboardAction != null) {
          _onSendClipboardAction!();
        } else {
          // Queue for when the callback gets registered
          _pendingAction = action;
          debugPrint('[ForegroundService] Queued action: $action (callback not ready yet)');
        }
        break;
      case 'send_files':
      case 'pick_files':
        if (_onSendFilesAction != null) {
          _onSendFilesAction!();
        } else {
          // Queue for when the callback gets registered
          _pendingAction = action;
          debugPrint('[ForegroundService] Queued action: $action (callback not ready yet)');
        }
        break;
    }
  }
}
