import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  /// Opaque cover shown while the app is backgrounded, so the OS app-switcher
  /// snapshot captures a blank brand screen instead of the user's balances, IBANs
  /// and transactions. Added on entering the background and removed on returning.
  ///
  /// Deliberately NOT `sceneWillResignActive`/`sceneDidBecomeActive` — those also
  /// fire for TEMPORARY system overlays that don't background the app at all
  /// (StoreKit's purchase-confirmation sheet, Face ID/Side-button prompts, Control
  /// Center), so the cover was blacking out the Apple Pay/Sandbox purchase sheet.
  /// `didEnterBackground`/`willEnterForeground` fire only for a real background.
  private var privacyCover: UIView?

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
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

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
