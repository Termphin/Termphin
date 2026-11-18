import ActivityKit
import Foundation

/// Shared ActivityKit payload compiled into both `Runner` and
/// `TransferActivityWidgetExtension` so their `ContentState` schemas match.
@available(iOS 16.2, *)
struct TransferActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var fileName: String
    var progress: Double
    var indeterminate: Bool
    var subtitle: String
    var shortText: String
    var completed: Bool
  }

  var transferId: Int
  var isUpload: Bool
}
