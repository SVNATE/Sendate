import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// Native clipboard listener that works even when Flutter window is NOT focused.
/// Uses platform channels to get real system clipboard changes from ANY app.
class NativeClipboardListener {
  static const _channel = MethodChannel('com.svnate.sendate/native_clipboard');
  final _log = const AppLogger('NativeClipboard');
  final _changeController = StreamController<String>.broadcast();
  String? _lastContent;
  Timer? _linuxTimer;

  /// Stream of clipboard text changes (fires when user copies in ANY app)
  Stream<String> get clipboardChanges => _changeController.stream;

  /// Start listening for native clipboard changes
  void start() {
    debugPrint('[NativeClipboard] start() called on platform: ${Platform.operatingSystem}');
    if (Platform.isMacOS || Platform.isAndroid || Platform.isIOS) {
      // macOS/Android/iOS: native listener sends events via method channel
      _channel.setMethodCallHandler(_handleNativeCallback);
      // Tell native to start monitoring (macOS)
      if (Platform.isMacOS) {
        _channel.invokeMethod('startMonitoring');
      }
    } else if (Platform.isWindows) {
      // Windows: use native Win32 AddClipboardFormatListener + Dart timer fallback
      // The native listener may not always deliver WM_CLIPBOARDUPDATE reliably
      // in all Flutter window configurations, so we use a fast poll as backup.
      _channel.setMethodCallHandler(_handleNativeCallback);
      _channel.invokeMethod('startMonitoring').then((_) {
        debugPrint('[NativeClipboard] Windows: startMonitoring invoked successfully');
      }).catchError((e) {
        debugPrint('[NativeClipboard] Windows: startMonitoring FAILED: $e');
      });
      // Fast poll every 300ms as reliable fallback (uses native getClipboard)
      _startWindowsPolling();
    } else if (Platform.isLinux) {
      // Linux: poll using xclip/xsel
      _startLinuxPolling();
    }
  }

  /// Stop listening
  void stop() {
    _linuxTimer?.cancel();
    _linuxTimer = null;
    if (Platform.isMacOS || Platform.isWindows) {
      _channel.invokeMethod('stopMonitoring');
    }
  }

  /// Set the system clipboard (from any platform)
  Future<void> setClipboard(String text) async {
    _lastContent = text; // Prevent echo
    try {
      await _channel.invokeMethod('setClipboard', text);
    } catch (e) {
      _log.debug('setClipboard via channel failed, using fallback: $e');
      // Fallback to Flutter clipboard
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Get current clipboard content natively
  Future<String> getClipboard() async {
    try {
      final result = await _channel.invokeMethod<String>('getClipboard');
      if (result == null || result.isEmpty) {
        _log.debug('getClipboard returned empty from native channel');
      }
      return result ?? '';
    } catch (e) {
      _log.debug('getClipboard via channel failed, using fallback: $e');
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text ?? '';
    }
  }

  /// Handle callbacks from native code
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    debugPrint('[NativeClipboard] Received callback: ${call.method}, args type: ${call.arguments?.runtimeType}');
    if (call.method == 'onClipboardChanged') {
      final text = call.arguments as String? ?? '';
      
      // Handle debug messages from native
      if (text.startsWith('__DEBUG__:')) {
        debugPrint('[NativeClipboard] NATIVE DEBUG: ${text.substring(10)}');
        return;
      }
      
      debugPrint('[NativeClipboard] onClipboardChanged: text length=${text.length}, lastContent length=${_lastContent?.length ?? 0}, same=${text == _lastContent}');
      if (text.isNotEmpty && text != _lastContent) {
        _lastContent = text;
        debugPrint('[NativeClipboard] Broadcasting clipboard change to stream listeners (hasListener=${_changeController.hasListener})');
        _changeController.add(text);
      } else if (text.isEmpty) {
        debugPrint('[NativeClipboard] Ignoring empty clipboard change');
      } else {
        debugPrint('[NativeClipboard] Ignoring duplicate clipboard content');
      }
    }
  }

  /// Windows: fast poll using native getClipboard (no PowerShell overhead)
  void _startWindowsPolling() {
    _linuxTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      try {
        final result = await _channel.invokeMethod<String>('getClipboard');
        final text = result ?? '';
        if (text.isNotEmpty && text != _lastContent) {
          _lastContent = text;
          _changeController.add(text);
        }
      } catch (e) {
        // Silently ignore — native channel might not be ready yet
      }
    });
  }

  /// Linux: poll xclip every 500ms
  void _startLinuxPolling() {
    _linuxTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final result = await Process.run('xclip', ['-selection', 'clipboard', '-o']);
        final text = (result.stdout as String).trim();
        if (text.isNotEmpty && text != _lastContent) {
          _lastContent = text;
          _changeController.add(text);
        }
      } catch (e) {
        // Try xsel as fallback
        try {
          final result = await Process.run('xsel', ['--clipboard', '--output']);
          final text = (result.stdout as String).trim();
          if (text.isNotEmpty && text != _lastContent) {
            _lastContent = text;
            _changeController.add(text);
          }
        } catch (e2) {
          _log.debug('Linux clipboard polling failed: $e2');
        }
      }
    });
  }

  /// Mark content as "from remote" to prevent echo
  void markAsRemote(String text) {
    _lastContent = text;
  }

  void dispose() {
    stop();
    _changeController.close();
  }
}
