import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Closing the window does not quit: the app decides that itself, keeping
  /// to the menu bar or quitting as the user chose, and a Mac app is expected
  /// to outlive its window anyway. Quitting is Cmd+Q or the menu bar item.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// A click on the Dock icon with the window hidden in the menu bar brings
  /// the window back, as it would for any app whose window was closed.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(self)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
