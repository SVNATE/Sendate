#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Parse command-line arguments.
  // When the OS opens files with Sendate (Send To / Open With), file paths are
  // passed as command-line arguments.  We forward them to Flutter via
  // dart_entrypoint_arguments so IncomingShareService can read them.
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Collect file-path arguments (non-flag arguments that point to existing files)
  std::vector<std::string> file_args;
  for (const auto& arg : command_line_arguments) {
    if (!arg.empty() && arg[0] != '-') {
      // Check if this looks like an existing file path
      DWORD attrs = ::GetFileAttributesA(arg.c_str());
      if (attrs != INVALID_FILE_ATTRIBUTES &&
          !(attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        file_args.push_back("--open-file=" + arg);
      }
    }
  }

  // Merge file args into entrypoint arguments so Dart can read them
  std::vector<std::string> entrypoint_args = command_line_arguments;
  entrypoint_args.insert(entrypoint_args.end(), file_args.begin(), file_args.end());
  project.set_dart_entrypoint_arguments(std::move(entrypoint_args));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Sendate", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
