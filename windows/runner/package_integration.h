#ifndef RUNNER_PACKAGE_INTEGRATION_H_
#define RUNNER_PACKAGE_INTEGRATION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <functional>
#include <memory>

// What changes when ShellVibe runs from its MSIX package (the Microsoft Store
// build) rather than from the Inno Setup installer or the portable zip.
//
// A packaged app cannot start at login through the Run key: the path it would
// register holds the package version and is gone after the next update, and
// the value outlives an uninstall. It declares a StartupTask in its manifest
// instead and turns that on and off here.

// Whether this process has package identity, i.e. was started from the MSIX.
bool IsRunningAsPackage();

// Whether Windows started this process through the manifest's StartupTask.
// The task cannot pass arguments, so the caller adds the start-hidden one.
bool WasActivatedByStartupTask();

// Runs a task on the platform thread. Method channel replies must be sent from
// there, and the StartupTask calls block, so they run on a worker that hands
// the reply back through this.
using PlatformThreadPoster = std::function<void(std::function<void()>)>;

// The `dev.shellvibe.app/launch_at_login` channel the Dart side's
// `WindowsStartupTaskLaunchAtLogin` talks to, the same one macOS registers.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateLaunchAtLoginChannel(flutter::BinaryMessenger* messenger,
                           PlatformThreadPoster post);

#endif  // RUNNER_PACKAGE_INTEGRATION_H_
