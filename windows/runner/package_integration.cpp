#include "package_integration.h"

#include <windows.h>
#include <appmodel.h>

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>

#include <string>
#include <thread>
#include <utility>

namespace {

using winrt::Windows::ApplicationModel::StartupTask;
using winrt::Windows::ApplicationModel::StartupTaskState;

// Must match the TaskId in tool/packaging/windows_msix/AppxManifest.xml.
constexpr wchar_t kStartupTaskId[] = L"ShellVibeStartup";

bool IsOn(StartupTaskState state) {
  return state == StartupTaskState::Enabled ||
         state == StartupTaskState::EnabledByPolicy;
}

using Result = flutter::MethodResult<flutter::EncodableValue>;

// Reads, and for setEnabled changes, the task off the platform thread, then
// replies on it.
void RunStartupTaskCall(std::shared_ptr<Result> result,
                        const PlatformThreadPoster& post, bool change,
                        bool enable) {
  std::thread([result, post, change, enable]() {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    std::function<void()> reply;
    try {
      StartupTask task = StartupTask::GetAsync(kStartupTaskId).get();
      StartupTaskState state = task.State();
      if (change && enable && !IsOn(state)) {
        // A desktop app is enabled without a prompt, unless the user or a
        // policy turned the task off, which only they can undo.
        state = task.RequestEnableAsync().get();
      } else if (change && !enable && IsOn(state)) {
        task.Disable();
        state = task.State();
      }

      if (change && enable && state == StartupTaskState::DisabledByUser) {
        reply = [result]() {
          result->Error("disabled_by_user",
                        "Start at login was turned off in Task Manager or "
                        "Settings > Apps > Startup. Turn ShellVibe on there.");
        };
      } else if (change && enable &&
                 state == StartupTaskState::DisabledByPolicy) {
        reply = [result]() {
          result->Error("disabled_by_policy",
                        "Start at login is turned off by a policy on this "
                        "computer.");
        };
      } else if (change) {
        reply = [result]() { result->Success(); };
      } else {
        const bool on = IsOn(state);
        reply = [result, on]() { result->Success(flutter::EncodableValue(on)); };
      }
    } catch (const winrt::hresult_error& error) {
      const std::string message = winrt::to_string(error.message());
      reply = [result, message]() { result->Error("startup_task", message); };
    }
    winrt::uninit_apartment();
    post(std::move(reply));
  }).detach();
}

}  // namespace

bool IsRunningAsPackage() {
  UINT32 length = 0;
  return ::GetCurrentPackageFullName(&length, nullptr) !=
         APPMODEL_ERROR_NO_PACKAGE;
}

bool WasActivatedByStartupTask() {
  if (!IsRunningAsPackage()) return false;
  try {
    const auto args =
        winrt::Windows::ApplicationModel::AppInstance::GetActivatedEventArgs();
    return args &&
           args.Kind() == winrt::Windows::ApplicationModel::Activation::
                              ActivationKind::StartupTask;
  } catch (const winrt::hresult_error&) {
    return false;
  }
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLaunchAtLoginChannel(flutter::BinaryMessenger* messenger,
                           PlatformThreadPoster post) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.shellvibe.app/launch_at_login",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [post](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<Result> result) {
        const std::string& method = call.method_name();
        if (method == "isSupported") {
          result->Success(flutter::EncodableValue(IsRunningAsPackage()));
        } else if (method == "isEnabled") {
          RunStartupTaskCall(std::shared_ptr<Result>(std::move(result)), post,
                             false, false);
        } else if (method == "setEnabled") {
          const auto* enable = std::get_if<bool>(call.arguments());
          if (enable == nullptr) {
            result->Error("bad_args", "setEnabled takes a bool.");
            return;
          }
          RunStartupTaskCall(std::shared_ptr<Result>(std::move(result)), post,
                             true, *enable);
        } else if (method == "wasLaunchedAtLogin") {
          result->Success(flutter::EncodableValue(WasActivatedByStartupTask()));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
