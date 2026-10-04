#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <functional>
#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Whether the window shows itself if the first frame is in and nothing has
  // shown it a few seconds later. Off for a launch that is meant to stay
  // hidden. Call before Create.
  void SetShowFallback(bool enabled) { show_fallback_ = enabled; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  bool show_fallback_ = true;

  // Start at login for the MSIX build; see package_integration.h. Null when
  // the app runs unpackaged and the Dart side writes the Run key itself.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      launch_at_login_channel_;

  // Queues |task| to run on this window's thread, the platform thread.
  void PostToPlatformThread(std::function<void()> task);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
