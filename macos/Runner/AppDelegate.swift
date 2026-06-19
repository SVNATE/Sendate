import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSMenuDelegate {
  var clipboardChannel: FlutterMethodChannel?
  var trayChannel: FlutterMethodChannel?
  var lastChangeCount: Int = 0
  var clipboardTimer: Timer?

  // Native system tray
  var statusItem: NSStatusItem?
  var trayMenu: NSMenu?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Don't quit when window closes — keep running in background (tray mode)
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    // When user clicks app icon in Dock or Launchpad while running, show the window
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      // Show Dock icon when window is visible
      NSApp.setActivationPolicy(.regular)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Set up clipboard monitoring channel
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      clipboardChannel = FlutterMethodChannel(
        name: "com.svnate.sendate/native_clipboard",
        binaryMessenger: controller.engine.binaryMessenger
      )

      // Set up native tray channel
      trayChannel = FlutterMethodChannel(
        name: "com.svnate.sendate/native_tray",
        binaryMessenger: controller.engine.binaryMessenger
      )

      // Handle tray method calls from Flutter
      trayChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "initTray":
          self?.initNativeTray()
          result(true)
        case "setMenu":
          if let args = call.arguments as? [[String: Any]] {
            self?.setNativeTrayMenu(items: args)
          }
          result(true)
        case "setIcon":
          if let iconName = call.arguments as? String {
            self?.setNativeTrayIcon(name: iconName)
          }
          result(true)
        case "setDockIconVisible":
          if let visible = call.arguments as? Bool {
            if visible {
              NSApp.setActivationPolicy(.regular)
            } else {
              NSApp.setActivationPolicy(.accessory)
            }
          }
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Handle clipboard method calls from Flutter
      clipboardChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "setClipboard":
          if let text = call.arguments as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self?.lastChangeCount = NSPasteboard.general.changeCount
          }
          result(true)
        case "getClipboard":
          let text = NSPasteboard.general.string(forType: .string) ?? ""
          result(text)
        case "startMonitoring":
          self?.startClipboardMonitoring()
          result(true)
        case "stopMonitoring":
          self?.stopClipboardMonitoring()
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Start monitoring immediately
      lastChangeCount = NSPasteboard.general.changeCount
      startClipboardMonitoring()
    }
  }

  // MARK: - Native Tray Implementation

  func initNativeTray() {
    if statusItem != nil { return }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // Set a default icon immediately
    setNativeTrayIcon(name: "tray_icon.png")
  }

  func setNativeTrayIcon(name: String) {
    guard let button = statusItem?.button else { return }

    // Try loading from xcassets first
    if let image = NSImage(named: "TrayIcon") {
      button.image = image
      button.image?.size = NSSize(width: 18, height: 18)
      button.image?.isTemplate = true
      return
    }

    // Try loading from Flutter assets bundle
    let bundle = Bundle.main
    let flutterAssetsPath = bundle.bundlePath + "/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/icons/\(name)"
    if let image = NSImage(contentsOfFile: flutterAssetsPath) {
      button.image = image
      button.image?.size = NSSize(width: 18, height: 18)
      button.image?.isTemplate = true
      return
    }

    // Fallback: try direct resource path
    if let resourcePath = bundle.path(forResource: "flutter_assets/assets/icons/\(name)", ofType: nil) {
      if let image = NSImage(contentsOfFile: resourcePath) {
        button.image = image
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
        return
      }
    }

    // Last resort: use a simple text icon
    button.title = "⇄"
    button.image = nil
  }

  func setNativeTrayMenu(items: [[String: Any]]) {
    let menu = NSMenu()
    menu.delegate = self

    for item in items {
      let type = item["type"] as? String ?? "normal"
      let label = item["label"] as? String ?? ""
      let key = item["key"] as? String ?? ""
      let disabled = item["disabled"] as? Bool ?? false

      if type == "separator" {
        menu.addItem(NSMenuItem.separator())
      } else {
        let menuItem = NSMenuItem(
          title: label,
          action: disabled ? nil : #selector(trayMenuItemClicked(_:)),
          keyEquivalent: ""
        )
        menuItem.target = self
        menuItem.isEnabled = !disabled
        menuItem.representedObject = key
        menu.addItem(menuItem)
      }
    }

    trayMenu = menu
    statusItem?.menu = menu
  }

  @objc func trayMenuItemClicked(_ sender: NSMenuItem) {
    guard let key = sender.representedObject as? String, !key.isEmpty else { return }
    // Send the click event back to Flutter
    trayChannel?.invokeMethod("onMenuItemClick", arguments: key)
  }

  // NSMenuDelegate
  public func menuDidClose(_ menu: NSMenu) {
    // Keep menu assigned — macOS handles showing/hiding automatically
  }

  // MARK: - Clipboard Monitoring

  func startClipboardMonitoring() {
    clipboardTimer?.invalidate()
    clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      let currentCount = NSPasteboard.general.changeCount
      if currentCount != self.lastChangeCount {
        self.lastChangeCount = currentCount
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if !text.isEmpty {
          // Send to Flutter
          DispatchQueue.main.async {
            self.clipboardChannel?.invokeMethod("onClipboardChanged", arguments: text)
          }
        }
      }
    }
  }

  func stopClipboardMonitoring() {
    clipboardTimer?.invalidate()
    clipboardTimer = nil
  }
}
