import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
@main
struct TransferActivityBundle: WidgetBundle {
  var body: some Widget {
    TransferActivityWidget()
  }
}

@available(iOS 16.2, *)
struct TransferActivityWidget: Widget {
  private static let accentBlue = Color(red: 0.30, green: 0.64, blue: 1.0)
  private static let doneGreen = Color(red: 0.38, green: 0.85, blue: 0.60)

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TransferActivityAttributes.self) { context in
      lockScreenView(context: context)
        .activityBackgroundTint(Color(red: 0.05, green: 0.08, blue: 0.10))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text(context.attributes.isUpload ? "Upload" : "Download")
              .font(.caption.weight(.semibold))
          } icon: {
            statusIcon(context: context)
          }
          .foregroundStyle(tintColor(context: context))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.shortText)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(tintColor(context: context))
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(context.attributes.fileName)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)
            progressBar(context: context)
            if !context.state.subtitle.isEmpty {
              Text(context.state.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      } compactLeading: {
        statusIcon(context: context)
          .foregroundStyle(tintColor(context: context))
      } compactTrailing: {
        Text(context.state.shortText)
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(tintColor(context: context))
      } minimal: {
        statusIcon(context: context)
          .foregroundStyle(tintColor(context: context))
      }
    }
  }

  @ViewBuilder
  private func lockScreenView(context: ActivityViewContext<TransferActivityAttributes>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        statusIcon(context: context)
          .font(.title3)
          .foregroundStyle(tintColor(context: context))
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.fileName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
          if !context.state.subtitle.isEmpty {
            Text(context.state.subtitle)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.72))
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        Text(context.state.shortText)
          .font(.subheadline.monospacedDigit().weight(.semibold))
          .foregroundStyle(tintColor(context: context))
      }
      progressBar(context: context)
    }
    .padding(14)
  }

  @ViewBuilder
  private func progressBar(context: ActivityViewContext<TransferActivityAttributes>) -> some View {
    if context.state.indeterminate && !context.state.completed {
      ProgressView()
        .progressViewStyle(.linear)
        .tint(Self.accentBlue)
    } else {
      ProgressView(value: context.state.progress)
        .progressViewStyle(.linear)
        .tint(tintColor(context: context))
    }
  }

  private func statusIcon(context: ActivityViewContext<TransferActivityAttributes>) -> Image {
    if context.state.completed {
      return Image(systemName: "checkmark.circle.fill")
    }
    return Image(
      systemName: context.attributes.isUpload ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    )
  }

  private func tintColor(context: ActivityViewContext<TransferActivityAttributes>) -> Color {
    context.state.completed ? Self.doneGreen : Self.accentBlue
  }
}
