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
  }
}
