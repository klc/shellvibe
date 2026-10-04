#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "package_integration.h"

namespace {

// Carries a heap-allocated std::function<void()> in its LPARAM.
constexpr UINT kRunOnPlatformThread = WM_APP + 0x51;

// Shows the window if the Dart side has not, a while after the first frame.
constexpr UINT_PTR kShowFallbackTimer = 1;
constexpr UINT kShowFallbackDelayMs = 3000;

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
