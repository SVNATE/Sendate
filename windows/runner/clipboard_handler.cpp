#include "clipboard_handler.h"

#include <flutter/encodable_value.h>
#include <windows.h>

#include <codecvt>
#include <locale>
#include <string>

// Static instance pointer for the WndProc callback
static ClipboardHandler* g_clipboard_handler = nullptr;

// WndProc for the hidden clipboard-monitoring window
static LRESULT CALLBACK ClipboardWndProc(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  if (message == WM_CLIPBOARDUPDATE && g_clipboard_handler) {
    g_clipboard_handler->OnClipboardChanged();
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

ClipboardHandler::ClipboardHandler() {}

ClipboardHandler::~ClipboardHandler() { StopMonitoring(); }

void ClipboardHandler::Register(flutter::FlutterEngine* engine) {
  engine_ = engine;
  g_clipboard_handler = this;

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "com.svnate.sendate/native_clipboard",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "startMonitoring") {
          // Already started via StartMonitoring() in OnCreate
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

void ClipboardHandler::StartMonitoring(HWND /* parent - unused now */) {
  if (monitoring_) return;

  // Create a hidden message-only window dedicated to clipboard monitoring.
  // This avoids interference from Flutter's own message handling on the main window.
  const wchar_t* kClassName = L"SendateClipboardListener";

  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.lpfnWndProc = ClipboardWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  RegisterClassExW(&wc);

  // HWND_MESSAGE windows may not receive WM_CLIPBOARDUPDATE on some Windows
  // versions. Use a regular hidden window (WS_POPUP, zero size, not shown).
  hwnd_ = CreateWindowExW(0, kClassName, L"", WS_POPUP, 0, 0, 0, 0, nullptr,
                          nullptr, GetModuleHandle(nullptr), nullptr);

  if (!hwnd_) {
    return;
  }

  if (AddClipboardFormatListener(hwnd_)) {
    monitoring_ = true;
    last_content_ = GetClipboardText();
  } else {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void ClipboardHandler::StopMonitoring() {
  if (monitoring_ && hwnd_) {
    RemoveClipboardFormatListener(hwnd_);
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
    monitoring_ = false;
  }
}

bool ClipboardHandler::HandleWindowMessage(HWND hwnd, UINT message,
                                           WPARAM wparam, LPARAM lparam) {
  // No longer needed — we use a dedicated hidden window.
  // Keep the method for API compatibility but it's a no-op.
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
  if (!OpenClipboard(nullptr)) return "";

  std::string result;
  HANDLE hData = GetClipboardData(CF_UNICODETEXT);
  if (hData) {
    wchar_t* pData = static_cast<wchar_t*>(GlobalLock(hData));
    if (pData) {
      int size_needed = WideCharToMultiByte(CP_UTF8, 0, pData, -1, nullptr, 0,
                                            nullptr, nullptr);
      if (size_needed > 0) {
        result.resize(size_needed - 1);
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
  int wide_size =
      MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (wide_size <= 0) return false;

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
