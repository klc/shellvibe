#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cstring>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "package_integration.h"

namespace {

// Carries a heap-allocated std::function<void()> in its LPARAM.
constexpr UINT kRunOnPlatformThread = WM_APP + 0x51;

// Shows the window if the Dart side has not, a while after the first frame.
constexpr UINT_PTR kShowFallbackTimer = 1;
constexpr UINT kShowFallbackDelayMs = 3000;

// Hands |size| bytes to the open clipboard as |format|.
bool SetClipboardBytes(UINT format, const void* data, size_t size) {
  HGLOBAL memory = ::GlobalAlloc(GMEM_MOVEABLE, size);
  if (!memory) return false;
  void* target = ::GlobalLock(memory);
  if (!target) {
    ::GlobalFree(memory);
    return false;
  }
  std::memcpy(target, data, size);
  ::GlobalUnlock(memory);
  if (!::SetClipboardData(format, memory)) {
    ::GlobalFree(memory);
    return false;
  }
  return true;
}

// Puts |utf8| on the clipboard marked to stay out of clipboard history, cloud
// clipboard sync and clipboard monitors. On failure the clipboard is left
// empty, never holding the text without the marks.
bool CopySensitiveText(HWND owner, const std::string& utf8) {
  int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                     utf8.data(), static_cast<int>(utf8.size()),
                                     nullptr, 0);
  if (length <= 0 && !utf8.empty()) return false;
  std::wstring text(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                        static_cast<int>(utf8.size()), text.data(), length);
  if (!::OpenClipboard(owner)) return false;
  ::EmptyClipboard();
  const DWORD zero = 0;
  bool ok =
      SetClipboardBytes(::RegisterClipboardFormatW(
                            L"ExcludeClipboardContentFromMonitorProcessing"),
                        &zero, sizeof(zero)) &&
      SetClipboardBytes(
          ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory"), &zero,
          sizeof(zero)) &&
      SetClipboardBytes(
          ::RegisterClipboardFormatW(L"CanUploadToCloudClipboard"), &zero,
          sizeof(zero)) &&
      SetClipboardBytes(CF_UNICODETEXT, text.c_str(),
                        (text.size() + 1) * sizeof(wchar_t));
  if (!ok) ::EmptyClipboard();
  ::CloseClipboard();
  return ok;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  if (IsRunningAsPackage()) {
    launch_at_login_channel_ = CreateLaunchAtLoginChannel(
        flutter_controller_->engine()->messenger(),
        [this](std::function<void()> task) {
          PostToPlatformThread(std::move(task));
        });
  }
  // The Dart side's ClipboardAutoClearService copies secrets through here, and
  // falls back to a plain copy on an error.
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev.shellvibe.app/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* text = std::get_if<std::string>(call.arguments());
        if (call.method_name() != "copySensitive" || text == nullptr) {
          result->NotImplemented();
        } else if (CopySensitiveText(GetHandle(), *text)) {
          result->Success();
        } else {
          result->Error("copy_failed", "The clipboard could not be set.");
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The Dart side shows the window, maximised, through window_manager
  // (lib/main.dart). The template's Show() here used SW_SHOWNORMAL, which
  // restored the window to its normal size a moment after Dart maximised it,
  // so the app never opened maximised; and on a software renderer the
  // swapchain did not recover from that second resize, leaving the window
  // white. Showing here is now only a fallback for a Dart side that failed
  // before it could show the window.
  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (show_fallback_) {
      ::SetTimer(GetHandle(), kShowFallbackTimer, kShowFallbackDelayMs,
                 nullptr);
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  launch_at_login_channel_ = nullptr;
  clipboard_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kRunOnPlatformThread) {
    std::unique_ptr<std::function<void()>> task(
        reinterpret_cast<std::function<void()>*>(lparam));
    // A reply that arrives after the channel is gone has no one to answer.
    if (launch_at_login_channel_) (*task)();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_TIMER:
      if (wparam == kShowFallbackTimer) {
        ::KillTimer(hwnd, kShowFallbackTimer);
        if (!::IsWindowVisible(hwnd)) this->Show();
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::PostToPlatformThread(std::function<void()> task) {
  auto* heap = new std::function<void()>(std::move(task));
  if (!::PostMessage(GetHandle(), kRunOnPlatformThread, 0,
                     reinterpret_cast<LPARAM>(heap))) {
    // The window is gone, and with it anything the task would reply to.
    delete heap;
  }
}
