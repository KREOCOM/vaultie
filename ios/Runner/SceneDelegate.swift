import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  /// Opaque cover shown while the app is inactive, so the OS app-switcher snapshot
  /// captures a blank brand screen instead of the user's balances, IBANs and
  /// transactions. Added when the app resigns active (which is when iOS takes the
  /// snapshot) and removed when it becomes active again.
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard privacyCover == nil,
          let windowScene = scene as? UIWindowScene,
          let window = windowScene.windows.first else { return }
    let cover = UIView(frame: window.bounds)
    // Near-black brand background (matches the lock/splash), fully opaque.
    cover.backgroundColor = UIColor(red: 0.039, green: 0.035, blue: 0.063, alpha: 1)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
