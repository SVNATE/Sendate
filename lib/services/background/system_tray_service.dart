import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// System tray service — Soduto-style menu bar app.
///
/// On macOS: uses native NSStatusItem via method channel for reliable click handling.
/// On Windows/Linux: uses tray_manager as fallback.
///
/// Menu structure:
///   Devices                  (disabled header)
///   CPH2467                  (disabled device name)
///     Send Clipboard         (action)
///     Send Files             (action)
///   ─────────────
///   ✓ Launch on Login        (checkbox)
///   Open Sendate             (action)
///   ─────────────
///   Quit                     (action)
class SystemTrayService with TrayListener, WindowListener {
  static final SystemTrayService instance = SystemTrayService._();
  factory SystemTrayService() => instance;
  SystemTrayService._();

  VoidCallback? onOpenApp;
  VoidCallback? onQuit;
  void Function(String deviceName)? onSendClipboardToDevice;
  void Function(String deviceName)? onSendFilesToDevice;

  bool _initialized = false;
  bool _launchOnLogin = false;
  List<String> _currentDevices = [];

  bool get isInitialized => _initialized;
  List<String> get currentDevices => _currentDevices;

  // Native tray channel for macOS
  static const _nativeTrayChannel = MethodChannel('com.svnate.sendate/native_tray');

  /// Initialize system tray (desktop only)
  Future<void> init() async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    if (_initialized) return;
    _initialized = true;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    // Don't hide window on launch — let the app show normally (visible in Dock & Launchpad)
    // User can close the window to go to tray-only mode

    // Check current launch-on-login state
    _launchOnLogin = await _isLaunchOnLoginEnabled();

    if (Platform.isMacOS) {
      // Use native macOS tray implementation for reliable click handling
      _nativeTrayChannel.setMethodCallHandler(_handleNativeTrayCall);
      await _nativeTrayChannel.invokeMethod('initTray');
      await _nativeTrayChannel.invokeMethod('setIcon', 'tray_icon.png');
    } else {
      // Windows/Linux: use tray_manager
      trayManager.addListener(this);
      await trayManager.setIcon(_getTrayIconPath());
    }

    await _rebuildMenu();
  }

  /// Handle calls from native macOS tray
  Future<void> _handleNativeTrayCall(MethodCall call) async {
    if (call.method == 'onMenuItemClick') {
      final key = call.arguments as String? ?? '';
      debugPrint('[Tray] Native menu item clicked: key=$key');
      _handleMenuClick(key);
    }
  }

  /// Update with discovered devices
  Future<void> updateConnectedDevices(List<String> deviceNames) async {
    if (!_initialized) return;
    _currentDevices = deviceNames;
    await _rebuildMenu();
  }

  /// Rebuild the tray menu
  Future<void> _rebuildMenu() async {
    if (Platform.isMacOS) {
      await _rebuildNativeMenu();
    } else {
      await _rebuildTrayManagerMenu();
    }
  }

  /// Build native macOS menu via method channel
  Future<void> _rebuildNativeMenu() async {
    final items = <Map<String, dynamic>>[];

    // --- Devices section ---
    items.add({'type': 'normal', 'label': 'Devices', 'key': '', 'disabled': true});

    if (_currentDevices.isNotEmpty) {
      for (final name in _currentDevices) {
        items.add({'type': 'normal', 'label': name, 'key': '', 'disabled': true});
        items.add({'type': 'normal', 'label': '  Send Clipboard', 'key': 'clip_$name', 'disabled': false});
        items.add({'type': 'normal', 'label': '  Send Files', 'key': 'file_$name', 'disabled': false});
      }
    } else {
      items.add({'type': 'normal', 'label': 'No devices nearby', 'key': '', 'disabled': true});
    }

    items.add({'type': 'separator'});

    // --- App actions ---
    items.add({
      'type': 'normal',
      'label': _launchOnLogin ? '✓ Launch on Login' : '  Launch on Login',
      'key': 'launch_on_login',
      'disabled': false,
    });
    items.add({'type': 'normal', 'label': 'Open Sendate', 'key': 'open', 'disabled': false});
    items.add({'type': 'separator'});
    items.add({'type': 'normal', 'label': 'Quit', 'key': 'quit', 'disabled': false});

    await _nativeTrayChannel.invokeMethod('setMenu', items);
  }

  /// Build tray_manager menu for Windows/Linux
  Future<void> _rebuildTrayManagerMenu() async {
    final items = <MenuItem>[];

    items.add(MenuItem(label: 'Devices', disabled: true));

    if (_currentDevices.isNotEmpty) {
      for (final name in _currentDevices) {
        items.add(MenuItem(label: name, disabled: true));
        items.add(MenuItem(
          key: 'clip_$name',
          label: '  Send Clipboard',
          onClick: (_) => _handleMenuClick('clip_$name'),
        ));
        items.add(MenuItem(
          key: 'file_$name',
          label: '  Send Files',
          onClick: (_) => _handleMenuClick('file_$name'),
        ));
      }
    } else {
      items.add(MenuItem(label: 'No devices nearby', disabled: true));
    }

    items.add(MenuItem.separator());

    items.add(MenuItem(
      key: 'launch_on_login',
      label: _launchOnLogin ? '✓ Launch on Login' : '  Launch on Login',
      onClick: (_) => _handleMenuClick('launch_on_login'),
    ));
    items.add(MenuItem(
      key: 'open',
      label: 'Open Sendate',
      onClick: (_) => _handleMenuClick('open'),
    ));
    items.add(MenuItem.separator());
    items.add(MenuItem(
      key: 'quit',
      label: 'Quit',
      onClick: (_) => _handleMenuClick('quit'),
    ));

    await trayManager.setContextMenu(Menu(items: items));
  }

  /// Centralized menu click handler
  void _handleMenuClick(String key) {
    debugPrint('[Tray] Menu action: $key');

    if (key.startsWith('clip_')) {
      final device = key.substring(5);
      debugPrint('[Tray] Send Clipboard to: $device');
      onSendClipboardToDevice?.call(device);
    } else if (key.startsWith('file_')) {
      final device = key.substring(5);
      debugPrint('[Tray] Send Files to: $device');
      onSendFilesToDevice?.call(device);
    } else {
      switch (key) {
        case 'launch_on_login':
          _toggleLaunchOnLogin();
        case 'open':
          _showWindow();
        case 'quit':
          _quitApp();
      }
    }
  }

  // --- TrayListener (Windows/Linux only) ---

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key.isNotEmpty) {
      _handleMenuClick(key);
    }
  }

  // --- Common actions ---

  void _toggleLaunchOnLogin() async {
    _launchOnLogin = !_launchOnLogin;
    if (_launchOnLogin) {
      await _enableLaunchOnLogin();
    } else {
      await _disableLaunchOnLogin();
    }
    await _rebuildMenu();
  }

  @override
  void onWindowClose() {
    // Hide window and remove from Dock (tray-only mode)
    windowManager.hide();
    if (Platform.isMacOS) {
      // Hide Dock icon when window is closed — app stays in menu bar only
      // This is the KDE Connect / Soduto behavior
      _setDockIconVisible(false);
    }
  }

  Future<void> _showWindow() async {
    if (Platform.isMacOS) {
      // Show Dock icon when window is visible
      _setDockIconVisible(true);
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// Toggle macOS Dock icon visibility using NSApplication activation policy
  void _setDockIconVisible(bool visible) {
    if (!Platform.isMacOS) return;
    try {
      _nativeTrayChannel.invokeMethod(
        'setDockIconVisible',
        visible,
      );
    } catch (_) {}
  }

  void _quitApp() {
    onQuit?.call();
    exit(0);
  }

  String _getTrayIconPath() {
    if (Platform.isMacOS) return 'assets/icons/tray_icon.png';
    if (Platform.isWindows) return 'assets/icons/tray_icon.ico';
    return 'assets/icons/tray_icon.png';
  }

  // --- Launch on Login (macOS LaunchAgent / Linux autostart) ---

  String get _launchAgentPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/Library/LaunchAgents/com.svnate.sendate.plist';
  }

  Future<bool> _isLaunchOnLoginEnabled() async {
    if (Platform.isMacOS) {
      return File(_launchAgentPath).existsSync();
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      return File('$home/.config/autostart/sendate.desktop').existsSync();
    }
    return false;
  }

  Future<void> _enableLaunchOnLogin() async {
    try {
      if (Platform.isMacOS) {
        final execPath = Platform.resolvedExecutable;
        final appBundlePath = execPath.contains('.app/Contents/MacOS/')
            ? execPath.substring(0, execPath.indexOf('.app/') + 4)
            : execPath;

        final plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.svnate.sendate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$appBundlePath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>''';

        final dir = Directory('${Platform.environment['HOME']}/Library/LaunchAgents');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File(_launchAgentPath).writeAsString(plist);
        debugPrint('[Tray] Launch on Login enabled: $_launchAgentPath');
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        final appPath = Platform.resolvedExecutable;
        final desktop = '''[Desktop Entry]
Type=Application
Name=Sendate
Exec=$appPath
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
''';
        final dir = Directory('$home/.config/autostart');
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('$home/.config/autostart/sendate.desktop')
            .writeAsString(desktop);
      }
    } catch (e) {
      debugPrint('[Tray] Enable launch on login error: $e');
    }
  }

  Future<void> _disableLaunchOnLogin() async {
    try {
      if (Platform.isMacOS) {
        final file = File(_launchAgentPath);
        if (await file.exists()) await file.delete();
        debugPrint('[Tray] Launch on Login disabled');
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/.config/autostart/sendate.desktop');
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('[Tray] Disable launch on login error: $e');
    }
  }

  void dispose() {
    if (!Platform.isMacOS) {
      trayManager.removeListener(this);
    }
    windowManager.removeListener(this);
  }
}
