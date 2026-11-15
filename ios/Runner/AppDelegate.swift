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
    AppIconPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "AppIconPlugin"))
  }
}

/// App 图标切换（2026-11-16，iOS 备用图标机制）：
/// get → 当前备用图标名（未换过 = nil）；set(name) → 换图标，空串 = 恢复默认
/// （setAlternateIconName(nil)）。成功后 iOS 自动弹系统确认框，主屏图标即时生效。
/// 备用图标集：Assets.xcassets 里 AppIconNight/Patrick/Sponge 三个 appiconset，
/// 经 Runner 构建设置 ASSETCATALOG_COMPILER_ALTERNATE_APP_ICON_NAMES 登记。
class AppIconPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "app.icon", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppIconPlugin(), channel: channel)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "get":
      result(UIApplication.shared.alternateIconName)
    case "set":
      let raw = (call.arguments as? [String: Any])?["name"] as? String ?? ""
      let target: String? = raw.isEmpty ? nil : raw
      UIApplication.shared.setAlternateIconName(target) { error in
        if let error {
          result(FlutterError(code: "icon_failed",
                              message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
