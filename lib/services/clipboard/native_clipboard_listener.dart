import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Native clipboard listener that works even when Flutter window is NOT focused.
/// Uses platform channels to get real system clipboard changes from ANY app.
class NativeClipboardListener {
  static const _channel = MethodChannel('com.svnate.sendate/native_clipboard');
  final _changeController = StreamController<String>.broadcast();
  String? _lastContent;
  Timer? _linuxTimer;

  /// Stream of clipboard text changes (fires when user copies in ANY app)
  Stream<String> get clipboardChanges => _changeController.stream;

  /// Start listening for native clipboard changes
  void start() {
    if (Platform.isMacOS || Platform.isAndroid || Platform.isIOS) {
      // macOS/Android/iOS: native listener sends events via method channel
      _channel.setMethodCallHandler(_handleNativeCallback);
      // Tell native to start monitoring (macOS)
      if (Platform.isMacOS) {
        _channel.invokeMethod('startMonitoring');
      }
    } else if (Platform.isLinux) {
      // Linux: poll using xclip/xsel
      _startLinuxPolling();
    } else if (Platform.isWindows) {
      // Windows: poll using PowerShell (simple approach)
      _startWindowsPolling();
    }
  }

  /// Stop listening
  void stop() {
    _linuxTimer?.cancel();
    _linuxTimer = null;
    if (Platform.isMacOS) {
      _channel.invokeMethod('stopMonitoring');
    }
  }

  /// Set the system clipboard (from any platform)
  Future<void> setClipboard(String text) async {
    _lastContent = text; // Prevent echo
    try {
      await _channel.invokeMethod('setClipboard', text);
    } catch (_) {
      // Fallback to Flutter clipboard
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Get current clipboard content natively
  Future<String> getClipboard() async {
    try {
      final result = await _channel.invokeMethod<String>('getClipboard');
      return result ?? '';
    } catch (_) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text ?? '';
    }
  }

  /// Handle callbacks from native code
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onClipboardChanged') {
      final text = call.arguments as String? ?? '';
      if (text.isNotEmpty && text != _lastContent) {
        _lastContent = text;
        _changeController.add(text);
      }
    }
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
      } catch (_) {
        // Try xsel as fallback
        try {
          final result = await Process.run('xsel', ['--clipboard', '--output']);
          final text = (result.stdout as String).trim();
          if (text.isNotEmpty && text != _lastContent) {
            _lastContent = text;
            _changeController.add(text);
          }
        } catch (_) {}
      }
    });
  }

  /// Windows: poll using PowerShell
  void _startWindowsPolling() {
    _linuxTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      try {
        final result = await Process.run(
          'powershell',
          ['-command', 'Get-Clipboard'],
        );
        final text = (result.stdout as String).trim();
        if (text.isNotEmpty && text != _lastContent) {
          _lastContent = text;
          _changeController.add(text);
        }
      } catch (_) {}
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
