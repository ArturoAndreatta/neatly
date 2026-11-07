#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Espelho de ALLOC_CONSOLE_OPTIONS (consoleapi.h, Windows 11 24H2+), para
// compilar com SDK mais antigo.
struct OpcoesConsole {
  int modo;  // 2 = ALLOC_CONSOLE_MODE_NO_WINDOW
  BOOL usarMostrar;
  WORD mostrar;
};
using AllocComOpcoes = HRESULT(WINAPI *)(OpcoesConsole *, int *);

// Console sem janela para o processo. Sem ele, cada programa de console
// que o app roda (o `claude`, o `reg`) ganha um console novo, e o Windows
// abre uma janela do terminal vazia na tela.
void CriarConsoleOculto() {
  if (auto alloc = reinterpret_cast<AllocComOpcoes>(::GetProcAddress(
          ::GetModuleHandleW(L"kernel32.dll"), "AllocConsoleWithOptions"))) {
    OpcoesConsole opcoes{2, FALSE, 0};
    int resultado = 0;
    if (SUCCEEDED(alloc(&opcoes, &resultado))) return;
  }
  // Windows mais antigo: um cmd sem janela cria o console, o app se liga
  // a ele e o cmd sai; o console fica enquanto o app estiver ligado.
  wchar_t linha[] = L"cmd.exe /c ping -n 3 127.0.0.1 >nul";
  STARTUPINFOW si{sizeof(si)};
  PROCESS_INFORMATION pi{};
  if (!::CreateProcessW(nullptr, linha, nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
    return;
  }
  for (int i = 0; i < 50 && !::AttachConsole(pi.dwProcessId); ++i) {
    ::Sleep(20);
  }
  ::TerminateProcess(pi.hProcess, 0);
  ::CloseHandle(pi.hThread);
  ::CloseHandle(pi.hProcess);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
    if (::IsDebuggerPresent()) {
      CreateAndAttachConsole();
    } else {
      CriarConsoleOculto();
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Rodada agendada: sem janela e sem trava de instância única.
  const bool agendado = wcsstr(command_line, L"--agendado") != nullptr;
  HANDLE trava = nullptr;
  if (!agendado) {
    // Já aberto: traz a janela existente para frente em vez de abrir outra.
    trava = ::CreateMutexW(nullptr, TRUE, L"NeatlyJanela");
    if (::GetLastError() == ERROR_ALREADY_EXISTS) {
      if (HWND aberta = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Neatly")) {
        ::ShowWindow(aberta, SW_RESTORE);
        ::SetForegroundWindow(aberta);
      }
      return EXIT_SUCCESS;
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(460, 640);
  if (!window.Create(L"Neatly", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (trava) ::CloseHandle(trava);
  return EXIT_SUCCESS;
}
