#include "clipboard_handler.h"

#include <flutter/encodable_value.h>

#include <codecvt>
#include <locale>

ClipboardHandler::ClipboardHandler() {}

ClipboardHandler::~ClipboardHandler() { StopMonitoring(); }

void ClipboardHandler::Register(flutter::FlutterEngine* engine) {
  engine_ = engine;

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "com.svnate.sendate/native_clipboard",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "startMonitoring") {
          // Already started via StartMonitoring(hwnd) in OnCreate
          result->Success();
        } else if (call.method_name() == "stopMonitoring") {
          StopMonitoring();
          result->Success();
        } else if (call.method_name() == "getClipboard") {
          std::string text = GetClipboardText();
          result->Success(flutter::EncodableValue(text));
        } else if (call.method_name() == "setClipboard") {
          const auto* args = std::get_if<std::string>(call.arguments());
          if (args) {
            suppress_next_change_ = true;
            bool ok = SetClipboardText(*args);
            if (ok) {
              last_content_ = *args;
              result->Success();
            } else {
              result->Error("CLIPBOARD_ERROR", "Failed to set clipboard");
            }
          } else {
            result->Error("INVALID_ARGUMENT", "Expected a string argument");
          }
        } else {
          result->NotImplemented();
        }
      });
}

void ClipboardHandler::StartMonitoring(HWND hwnd) {
  if (monitoring_) return;
  hwnd_ = hwnd;
  if (AddClipboardFormatListener(hwnd_)) {
    monitoring_ = true;
    // Capture the current clipboard content to avoid a false initial change
    last_content_ = GetClipboardText();
  }
}

void ClipboardHandler::StopMonitoring() {
  if (monitoring_ && hwnd_) {
    RemoveClipboardFormatListener(hwnd_);
    monitoring_ = false;
  }
}

bool ClipboardHandler::HandleWindowMessage(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLIPBOARDUPDATE) {
    OnClipboardChanged();
    return true;
  }
  return false;
}

void ClipboardHandler::OnClipboardChanged() {
  if (suppress_next_change_) {
    suppress_next_change_ = false;
    return;
  }

  std::string text = GetClipboardText();
  if (text.empty() || text == last_content_) return;

  last_content_ = text;

  // Notify Dart via the method channel
  if (channel_) {
    channel_->InvokeMethod("onClipboardChanged",
                           std::make_unique<flutter::EncodableValue>(text));
  }
}

std::string ClipboardHandler::GetClipboardText() {
  // Use nullptr to open clipboard without requiring a specific window to be active.
  // This ensures clipboard access works even when our window is hidden (system tray).
  if (!OpenClipboard(nullptr)) return "";

  std::string result;
  HANDLE hData = GetClipboardData(CF_UNICODETEXT);
  if (hData) {
    wchar_t* pData = static_cast<wchar_t*>(GlobalLock(hData));
    if (pData) {
      // Convert wide string to UTF-8
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, pData, -1, nullptr, 0,
                                            nullptr, nullptr);
      if (size_needed > 0) {
        result.resize(size_needed - 1);  // -1 to exclude null terminator
        WideCharToMultiByte(CP_UTF8, 0, pData, -1, &result[0], size_needed,
                            nullptr, nullptr);
      }
      GlobalUnlock(hData);
    }
  }

  CloseClipboard();
  return result;
}

bool ClipboardHandler::SetClipboardText(const std::string& text) {
  // Convert UTF-8 to wide string
  int wide_size =
      MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (wide_size <= 0) return false;

  // Use nullptr to open clipboard without requiring window focus
  if (!OpenClipboard(nullptr)) return false;

  EmptyClipboard();

  HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, wide_size * sizeof(wchar_t));
  if (!hGlobal) {
    CloseClipboard();
    return false;
  }

  wchar_t* pGlobal = static_cast<wchar_t*>(GlobalLock(hGlobal));
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, pGlobal, wide_size);
  GlobalUnlock(hGlobal);

  SetClipboardData(CF_UNICODETEXT, hGlobal);
  CloseClipboard();

  return true;
}
