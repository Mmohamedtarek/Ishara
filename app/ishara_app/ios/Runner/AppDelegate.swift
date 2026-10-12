import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Talk keeps the screen on while it is visible (S7-5); no package needed.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IsharaScreen") {
      FlutterMethodChannel(name: "ishara/screen", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          if call.method == "keepOn" {
            UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
            result(nil)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
  }
}
