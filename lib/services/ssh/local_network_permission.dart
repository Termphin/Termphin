import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the system dialog came back with.
enum LocalNetworkPermissionResult {
  granted,

  /// Refused this time; the dialog can be raised again.
  denied,

  /// Refused for good - the system will not show the dialog again, so the
  /// app's own settings page is the only way left to grant it.
  permanentlyDenied,
}

/// `ACCESS_LOCAL_NETWORK`, the permission an SSH client needs to reach a
/// machine on the user's own network.
///
/// Enforced from Android 17 against an app targeting API 37. Nothing is asked
/// for up front: most profiles point somewhere off the LAN, and a prompt about
/// discovering devices on the home network is a poor first impression for a
/// connection that never needed it. The connect path asks once it knows the
/// address is a local one - see [localNetworkPermissionRequired].
///
/// On iOS the status cannot be read without raising the prompt, so
/// [isGranted] reports false until [request] has run once.
class LocalNetworkPermission {
  LocalNetworkPermission._();

  static final instance = LocalNetworkPermission._();

  @visibleForTesting
  static const channel = MethodChannel('dev.termphin.termphin/local_network');

  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool? _enforced;

  /// Whether this device gates local traffic at all. Fixed for the life of the
  /// process, so it is read once.
  Future<bool> get isEnforced async {
    if (!supported) return false;
    return _enforced ??=
        await channel.invokeMethod<bool>('isEnforced') ?? false;
  }

  Future<bool> get isGranted async {
    if (!supported) return true;
    return await channel.invokeMethod<bool>('isGranted') ?? true;
  }

  Future<LocalNetworkPermissionResult> request() async {
    if (!supported) return LocalNetworkPermissionResult.granted;
    final result = await channel.invokeMethod<String>('request');
    return switch (result) {
      'granted' => LocalNetworkPermissionResult.granted,
      'permanentlyDenied' => LocalNetworkPermissionResult.permanentlyDenied,
      _ => LocalNetworkPermissionResult.denied,
    };
  }

  /// Opens this app's settings page. When there is nothing to open on this
  /// device, the row simply does nothing.
  Future<void> openAppSettings() async {
    if (!supported) return;
    try {
      await channel.invokeMethod('openAppSettings');
    } on PlatformException catch (_) {}
  }
}

/// Whether every one of [hosts] is on the local network.
///
/// All of them, not any: a profile whose fallback addresses include one off the
/// LAN still has somewhere to go, so the queue is worth attempting and a
/// failure at the end of it is about the machines, not about a permission.
/// Stops at the first that is not, which is also what keeps the lookups down.
Future<bool> allOnLocalNetwork(Iterable<String> hosts) async {
  var any = false;
  for (final host in hosts) {
    if (!await resolvesToLocalNetwork(host)) return false;
    any = true;
  }
  return any;
}

/// Whether reaching [host] means putting packets on the local network.
///
/// A literal is answered outright; a name is resolved, since the address the
/// system routes to is what the permission is keyed on and a name says nothing
/// about it. An `.local` name is mDNS, which is gated whether or not it
/// resolves. A name that fails to resolve at all is not a permission
/// problem, so it reports false rather than throwing.
Future<bool> resolvesToLocalNetwork(String host) async {
  final bare = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
  if (bare.toLowerCase().endsWith('.local')) return true;

  final literal = InternetAddress.tryParse(bare);
  if (literal != null) return isLocalNetworkAddress(literal);

  try {
    final addresses = await InternetAddress.lookup(bare);
    return addresses.any(isLocalNetworkAddress);
  } on SocketException {
    return false;
  }
}

/// Whether [address] sits on a directly-attached network.
///
/// Deliberately narrower than "not public". Loopback never leaves the device,
/// and 100.64.0.0/10 is where a VPN like Tailscale puts its peers - that
/// traffic is routed over a tunnel interface rather than the LAN, so it is not
/// what the permission gates and reporting it as blocked would send the user
/// after the wrong setting.
///
/// IPv4 covers 10/8, 172.16/12, 192.168/16 and 169.254/16 (link-local); IPv6
/// covers fe80::/10 (link-local) and fc00::/7 (unique local). An IPv4-mapped
/// IPv6 address carries the v4 rules with it.
bool isLocalNetworkAddress(InternetAddress address) {
  if (address.isLoopback) return false;
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return switch (bytes[0]) {
      10 => true,
      172 => bytes[1] >= 16 && bytes[1] <= 31,
      192 => bytes[1] == 168,
      169 => bytes[1] == 254,
      _ => false,
    };
  }
  if (address.type == InternetAddressType.IPv6) {
    if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
    if ((bytes[0] & 0xfe) == 0xfc) return true;
    if (_isIPv4Mapped(bytes)) {
      return isLocalNetworkAddress(
        InternetAddress.fromRawAddress(Uint8List.fromList(bytes.sublist(12))),
      );
    }
  }
  return false;
}

bool _isIPv4Mapped(List<int> bytes) {
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return false;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}
