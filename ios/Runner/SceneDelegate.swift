import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// Drawn over the window while the scene is inactive, so the app-switcher
  /// snapshot iOS takes then shows no terminal output or host list. A Dart
  /// auto-lock only lands on the way back in, after that snapshot was taken.
  private var privacyCover: UIView?
  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    // Notifications rather than overriding the delegate methods: those are
    // FlutterSceneDelegate's own, and they drive the app lifecycle in Dart.
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: UIScene.willDeactivateNotification, object: nil, queue: .main
      ) { [weak self] note in
        guard let self, note.object as? UIScene === self.window?.windowScene
        else { return }
        self.showPrivacyCover()
      },
      center.addObserver(
        forName: UIScene.didActivateNotification, object: nil, queue: .main
      ) { [weak self] note in
        guard let self, note.object as? UIScene === self.window?.windowScene
        else { return }
        self.privacyCover?.removeFromSuperview()
        self.privacyCover = nil
      },
    ]
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func showPrivacyCover() {
    guard privacyCover == nil, let window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .systemBackground
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }
}
