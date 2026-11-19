import ActivityKit
import Flutter
import Foundation

/// Bridges Dart's `TransferNotification` progress and completion updates onto
/// iOS ActivityKit Live Activities (iOS 16.2+).
enum TransferActivityChannel {
  static let name = "dev.termphin.termphin/live_activities"

  private static var activitiesStorage: Any?

  @available(iOS 16.2, *)
  private static var activities: [Int: Activity<TransferActivityAttributes>] {
    get {
      (activitiesStorage as? [Int: Activity<TransferActivityAttributes>]) ?? [:]
    }
    set {
      activitiesStorage = newValue
    }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: name,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "showProgress":
        showProgress(args)
        result(nil)
      case "showComplete":
        showComplete(args)
        result(nil)
      case "cancelNotification":
        cancel(args)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @available(iOS 16.2, *)
  private static func showProgress(_ args: [String: Any]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
      let id = args["id"] as? Int,
      let fileName = args["fileName"] as? String
    else { return }

    let rawProgress = args["progress"] as? Int ?? 0
    let indeterminate = rawProgress <= 0
    let fraction = min(max(Double(rawProgress) / 100.0, 0.0), 1.0)
    let isUpload = (args["shortText"] as? String)?.hasPrefix("↑") ?? false
    let subtitle = args["subtitle"] as? String ?? ""
    let shortText = args["shortText"] as? String ?? "\(rawProgress)%"

    let state = TransferActivityAttributes.ContentState(
      fileName: fileName,
      progress: fraction,
      indeterminate: indeterminate,
      subtitle: subtitle,
      shortText: shortText,
      completed: false
    )
    let content = ActivityContent(
      state: state,
      staleDate: Date().addingTimeInterval(300)
    )

    if let existing = activities[id] {
      Task { await existing.update(content) }
      return
    }

    let attributes = TransferActivityAttributes(
      transferId: id,
      isUpload: isUpload
    )
    if let created = try? Activity.request(
      attributes: attributes,
      content: content,
      pushType: nil
    ) {
      activities[id] = created
    }
  }

  @available(iOS 16.2, *)
  private static func showComplete(_ args: [String: Any]) {
    guard let id = args["id"] as? Int,
      let activity = activities.removeValue(forKey: id)
    else { return }

    let fileName = args["fileName"] as? String ?? activity.content.state.fileName
    let savedLabel = args["savedLabel"] as? String ?? "Done"
    let state = TransferActivityAttributes.ContentState(
      fileName: fileName,
      progress: 1.0,
      indeterminate: false,
      subtitle: savedLabel,
      shortText: "✓",
      completed: true
    )
    let content = ActivityContent(state: state, staleDate: nil)
    Task {
      await activity.end(
        content,
        dismissalPolicy: .after(Date().addingTimeInterval(4))
      )
    }
  }

  @available(iOS 16.2, *)
  private static func cancel(_ args: [String: Any]) {
    guard let id = args["id"] as? Int,
      let activity = activities.removeValue(forKey: id)
    else { return }

    let content = ActivityContent(
      state: activity.content.state,
      staleDate: nil
    )
    Task {
      await activity.end(content, dismissalPolicy: .immediate)
    }
  }
}
