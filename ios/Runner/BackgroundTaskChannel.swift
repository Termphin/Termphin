import Flutter
import UIKit

/// Hands Dart the `UIApplication` background-task grant.
///
/// This is not a foreground service and cannot stand in for one - the system
/// allows on the order of thirty seconds and then suspends the process anyway,
/// so it holds no SSH session open. It is enough for a file transfer already
/// in flight to finish writing rather than being cut off mid-file.
///
/// A grant held past its expiry is what makes the system kill the app instead
/// of suspending it, so `expirationHandler` ends it even if Dart never does.
enum BackgroundTaskChannel {
  static let name = "dev.termphin.termphin/background_task"

  private static var tasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private static var nextToken = 1

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: name,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "begin":
        let arguments = call.arguments as? [String: Any]
        let label = arguments?["name"] as? String ?? "transfer"
        result(begin(label))
      case "end":
        guard let arguments = call.arguments as? [String: Any],
          let token = arguments["token"] as? Int
        else {
          result(FlutterError(code: "BAD_ARGS", message: "token missing", details: nil))
          return
        }
        end(token)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func begin(_ label: String) -> Int {
    let token = nextToken
    nextToken += 1
    let identifier = UIApplication.shared.beginBackgroundTask(withName: label) {
      end(token)
    }
    if identifier == .invalid { return -1 }
    tasks[token] = identifier
    return token
  }

  private static func end(_ token: Int) {
    guard let identifier = tasks.removeValue(forKey: token) else { return }
    UIApplication.shared.endBackgroundTask(identifier)
  }
}
