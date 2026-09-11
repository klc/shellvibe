import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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
