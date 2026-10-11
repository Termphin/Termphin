import Flutter
import Network
import UIKit

/// The iOS side of the local network permission.
///
/// iOS has no API to query or request it. The only way to learn the answer is
/// to touch the local network and watch what happens, so this advertises a
/// Bonjour service and browses for it: seeing our own service means allowed,
/// a `PolicyDenied` from the browser means refused. The first such probe is
/// what raises the system prompt, which is why `isGranted` only probes once
/// `request` has been called - a status read must not ask the question.
enum LocalNetworkChannel {
  static let name = "dev.termphin.termphin/local_network"

  private static let askedKey = "local_network_asked"
  private static var probes: [LocalNetworkProbe] = []

  /// iOS asks once: a refusal after that is only undone in Settings, which is
  /// why a later `request` reports `permanentlyDenied` instead of `denied`.
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: name,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isEnforced":
        result(true)
      case "isGranted":
        guard UserDefaults.standard.bool(forKey: askedKey) else {
          result(false)
          return
        }
        probe(timeout: 5) { result($0) }
      case "request":
        let askedBefore = UserDefaults.standard.bool(forKey: askedKey)
        UserDefaults.standard.set(true, forKey: askedKey)
        probe(timeout: 60) { granted in
          result(granted ? "granted" : askedBefore ? "permanentlyDenied" : "denied")
        }
      case "openAppSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func probe(timeout: TimeInterval, _ completion: @escaping (Bool) -> Void) {
    let probe = LocalNetworkProbe()
    probes.append(probe)
    probe.run(timeout: timeout) { granted in
      probes.removeAll { $0 === probe }
      completion(granted)
    }
  }
}

private final class LocalNetworkProbe {
  /// Has to be listed under `NSBonjourServices` in Info.plist, or the browser
  /// is refused regardless of the permission.
  private static let serviceType = "_termphin._tcp"

  /// `kDNSServiceErr_PolicyDenied`: the user said no.
  private static let policyDenied = DNSServiceErrorType(-65570)

  private var listener: NWListener?
  private var browser: NWBrowser?
  private var completion: ((Bool) -> Void)?

  /// Includes peer-to-peer, which lets the browser see our own service with
  /// no Wi-Fi joined.
  func run(timeout: TimeInterval, _ completion: @escaping (Bool) -> Void) {
    self.completion = completion

    do {
      let listener = try NWListener(using: .tcp)
      listener.service = NWListener.Service(
        name: UUID().uuidString,
        type: Self.serviceType
      )
      listener.newConnectionHandler = { $0.cancel() }
      listener.stateUpdateHandler = { [weak self] state in
        if case .failed = state { self?.finish(false) }
      }
      self.listener = listener
      listener.start(queue: .main)
    } catch {
      finish(false)
      return
    }

    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: parameters
    )
    browser.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed:
        self?.finish(false)
      case .waiting(let error):
        if case .dns(Self.policyDenied) = error { self?.finish(false) }
      default:
        break
      }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      if !results.isEmpty { self?.finish(true) }
    }
    self.browser = browser
    browser.start(queue: .main)

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      self?.finish(false)
    }
  }

  private func finish(_ granted: Bool) {
    guard let completion else { return }
    self.completion = nil
    browser?.cancel()
    listener?.cancel()
    browser = nil
    listener = nil
    completion(granted)
  }
}
