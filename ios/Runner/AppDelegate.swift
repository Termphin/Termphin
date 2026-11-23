import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Without this delegate the system drops a notification posted while the
  /// app is in the foreground, which is when a transfer usually finishes.
  /// `FlutterAppDelegate` forwards the callbacks to every registered plugin.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackgroundTaskChannel.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: BackgroundTaskChannel.name
      )!
    )
    LocalNetworkChannel.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: LocalNetworkChannel.name
      )!
    )
    TransferActivityChannel.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: TransferActivityChannel.name
      )!
    )
    DeliveredNotificationsChannel.register(
      with: engineBridge.pluginRegistry.registrar(
        forPlugin: DeliveredNotificationsChannel.name
      )!
    )
  }
}

/// Takes pushes about a session out of Notification Center once that session
/// is opened. A push the system delivered while the app was closed is not the
/// notifications plugin's own, so it cannot cancel it; it is found here by
/// the machine and session its payload names, as `relay` in the functions
/// sends them.
enum DeliveredNotificationsChannel {
  static let name = "dev.termphin.termphin/delivered_notifications"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: name,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "removeRelayed",
        let args = call.arguments as? [String: Any],
        let profileId = args["profileId"] as? String,
        let session = args["session"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let center = UNUserNotificationCenter.current()
      center.getDeliveredNotifications { delivered in
        let ids = delivered
          .filter {
            let info = $0.request.content.userInfo
            return info["profileId"] as? String == profileId
              && info["session"] as? String == session
          }
          .map { $0.request.identifier }
        if !ids.isEmpty {
          center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        DispatchQueue.main.async { result(ids.count) }
      }
    }
  }
}
