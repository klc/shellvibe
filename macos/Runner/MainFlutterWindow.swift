import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app outlives its last window, so keep the window (and the Flutter
    // engine it hosts) alive after a close and re-show it on dock reopen.
    self.isReleasedWhenClosed = false

    registerLaunchAtLoginChannel(flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// Start at login, through `SMAppService.mainApp` (macOS 13+): the login item
  /// is the app itself, so there is no helper bundle to ship, and the user sees
  /// and can remove it under System Settings > General > Login Items.
  private func registerLaunchAtLoginChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev.shellvibe.app/launch_at_login",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "wasLaunchedAtLogin":
        result(AppDelegate.launchedAtLogin)
      case "isSupported":
        if #available(macOS 13.0, *) {
          result(true)
        } else {
          result(false)
        }
      case "isEnabled":
        if #available(macOS 13.0, *) {
          // "Requires approval" is registered, waiting on the user's switch in
          // Login Items; it is shown as on so the toggle does not fight them.
          let status = SMAppService.mainApp.status
          result(status == .enabled || status == .requiresApproval)
        } else {
          result(false)
        }
      case "setEnabled":
        guard #available(macOS 13.0, *) else {
          result(
            FlutterError(
              code: "unsupported", message: "Login items need macOS 13 or later", details: nil))
          return
        }
        let enable = (call.arguments as? Bool) ?? false
        do {
          if enable {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(nil)
        } catch {
          result(
            FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
