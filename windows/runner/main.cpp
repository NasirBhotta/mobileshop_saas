#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace
{

  constexpr wchar_t kAuthScheme[] = L"io.supabase.mobileshop";

  // Register the callback for unpackaged/debug Windows builds. This writes only
  // to the current user's registry hive and keeps the executable path quoted.
  // Packaged MSIX builds can additionally declare the same protocol in their
  // package manifest without changing the callback URL.
  bool RegisterAuthProtocol()
  {
    wchar_t executable_path[MAX_PATH] = {};
    const DWORD path_length =
        GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
    if (path_length == 0 || path_length >= MAX_PATH)
    {
      return false;
    }

    const std::wstring protocol_key =
        std::wstring(L"Software\\Classes\\") + kAuthScheme;
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, protocol_key.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS)
    {
      return false;
    }

    const std::wstring description = L"URL:MobileShop SaaS Auth Callback";
    const wchar_t empty_value[] = L"";
    const bool root_written =
        RegSetValueExW(
            key, nullptr, 0, REG_SZ,
            reinterpret_cast<const BYTE *>(description.c_str()),
            static_cast<DWORD>((description.size() + 1) * sizeof(wchar_t))) ==
            ERROR_SUCCESS &&
        RegSetValueExW(key, L"URL Protocol", 0, REG_SZ,
                       reinterpret_cast<const BYTE *>(empty_value),
                       sizeof(empty_value)) == ERROR_SUCCESS;
    RegCloseKey(key);
    if (!root_written)
    {
      return false;
    }

    const std::wstring command_key =
        protocol_key + L"\\shell\\open\\command";
    if (RegCreateKeyExW(HKEY_CURRENT_USER, command_key.c_str(), 0, nullptr, 0,
                        KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS)
    {
      return false;
    }

    const std::wstring command =
        L"\"" + std::wstring(executable_path) + L"\" \"%1\"";
    const bool command_written =
        RegSetValueExW(
            key, nullptr, 0, REG_SZ,
            reinterpret_cast<const BYTE *>(command.c_str()),
            static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t))) ==
        ERROR_SUCCESS;
    RegCloseKey(key);
    return command_written;
  }

} // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  RegisterAuthProtocol();

  // A protocol activation starts another process. Forward its URI to the
  // existing trusted instance, restore that window, and close this process.
  if (SendAppLinkToInstance())
  {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Nizaaam", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
