import Cocoa
import FlutterMacOS

/// Height of the app's own title bar (`kTitleBarHeight` in
/// lib/widgets/window/title_bar.dart), which the traffic lights sit in.
private let titleBarHeight: CGFloat = 36

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(centerTrafficLights), name: name, object: self)
    }
  }

  /// window_manager hides the system title bar from Dart once the app has
  /// started, which lays the buttons out again at the system's own height.
  override var styleMask: NSWindow.StyleMask {
    didSet { centerTrafficLights() }
  }

  /// Centres the close, minimise and zoom buttons in the app's title bar.
  ///
  /// The system draws them in a title bar of its own height, about 28pt,
  /// and the app's is taller, so left alone they sit above its middle. The
  /// container they live in is made as tall as the app's bar and the
  /// buttons are centred in it; AppKit lays them out again on a resize or
  /// on leaving full screen, so this runs after each.
  @objc private func centerTrafficLights() {
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let container = close.superview?.superview
    else { return }
    var frame = container.frame
    frame.size.height = titleBarHeight
    frame.origin.y = self.frame.height - titleBarHeight
    container.frame = frame
    for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = standardWindowButton(type) else { continue }
      let y = (titleBarHeight - button.frame.height) / 2
      button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
    }
  }
}
