#ifndef RUNNER_CLIPBOARD_HANDLER_H_
#define RUNNER_CLIPBOARD_HANDLER_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// Native Windows clipboard handler that uses WM_CLIPBOARDUPDATE
// for real-time clipboard change notifications (works even when
// Flutter window is not focused or is hidden in system tray).
class ClipboardHandler {
 public:
  ClipboardHandler();
  ~ClipboardHandler();

  // Register the method channel with the Flutter engine.
  void Register(flutter::FlutterEngine* engine);

  // Call from the main window's message handler to route clipboard messages.
  bool HandleWindowMessage(HWND hwnd, UINT message, WPARAM wparam,
                           LPARAM lparam);

  // Start monitoring clipboard changes (call after window is created).
  void StartMonitoring(HWND hwnd);

  // Stop monitoring clipboard changes.
  void StopMonitoring();

  // Called when WM_CLIPBOARDUPDATE is received on the hidden window.
  void OnClipboardChanged();

 private:
  // Get current clipboard text content using Win32 API.
  std::string GetClipboardText();

  // Set clipboard text content using Win32 API.
  bool SetClipboardText(const std::string& text);

  flutter::FlutterEngine* engine_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND hwnd_ = nullptr;
  bool monitoring_ = false;
  std::string last_content_;

  // Flag to suppress echo when we set the clipboard ourselves.
  bool suppress_next_change_ = false;
};

#endif  // RUNNER_CLIPBOARD_HANDLER_H_
