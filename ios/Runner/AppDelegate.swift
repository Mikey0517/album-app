import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// 整个 App 支持的方向。iPad 上只靠 SystemChrome 拦不住旋转，
  /// 这里在 App 层再收一道口子：默认竖屏，只有视频页才放开横屏。
  private var orientationMask: UIInterfaceOrientationMask = .portrait

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "album/orientation",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "detached", message: nil, details: nil))
          return
        }
        guard call.method == "setMask" else {
          result(FlutterMethodNotImplemented)
          return
        }
        switch (call.arguments as? String) ?? "portrait" {
        case "all":
          self.orientationMask = .allButUpsideDown
        case "landscape":
          self.orientationMask = .landscape
        default:
          self.orientationMask = .portrait
        }
        if #available(iOS 16.0, *) {
          self.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        UIViewController.attemptRotationToDeviceOrientation()
        result(nil)
      }

      // 补丁只在 Android 上，iOS 不会弹「更新已准备好」；这里只保证 Dart 侧
      // 万一调到这条通道时拿到明确的失败，而不是崩溃或挂住。
      FlutterMethodChannel(
        name: "album/app",
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        if call.method == "restart" {
          result(FlutterError(code: "unsupported", message: "iOS 不支持重启进程", details: nil))
          return
        }
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return orientationMask
  }
}
