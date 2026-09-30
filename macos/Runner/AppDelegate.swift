import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Whether the OS started this process as a login item. Read by the
  /// `launch_at_login` channel in MainFlutterWindow; the Dart side uses it to
  /// start with only the tray icon.
  static var launchedAtLogin = false

  override func applicationWillFinishLaunching(_ notification: Notification) {
    // The open-application event that started the process is only "current"
    // while the launch is being handled, so it is read here and kept. A login
    // item (SMAppService included) is launched with the login-item marker in
    // that event.
    let event = NSAppleEventManager.shared().currentAppleEvent
    AppDelegate.launchedAtLogin =
      event?.eventID == kAEOpenApplication
      && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        == keyAELaunchedAsLogInItem
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Keeps the window from flashing up before Dart has read the tray setting
    // and decided. Dart is the authority: a launch that is not to stay hidden
    // shows the window again as every launch does.
    if AppDelegate.launchedAtLogin {
      for window in NSApp.windows where window is MainFlutterWindow {
        window.orderOut(nil)
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Closing the last window hides the app instead of quitting it, which is
    // how a document-less macOS app is expected to behave. Quitting stays on
    // Cmd-Q / the app menu, and open SSH sessions survive a closed window.
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !flag else { return true }
    for window in sender.windows where window is MainFlutterWindow {
      window.makeKeyAndOrderFront(self)
      return true
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
