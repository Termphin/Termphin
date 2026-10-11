/// Where the user manual lives.
///
/// Part of the landing site, under /docs, so it gets its own constant rather
/// than hanging off [LegalUrls]. The app opens it in a web view rather than
/// bundling a copy: the manual is written against whatever version is current
/// and gets fixes between releases, so a bundled copy would be stale the
/// moment it shipped.
class ManualUrls {
  const ManualUrls._();

  static const home = 'https://termphin.dev/docs';

  /// The manual's old host, which now redirects every path into [home].
  static const _legacyHost = 'manual.termphin.dev';

  /// Whether [url] belongs to the manual, and so should open inside the web
  /// view rather than being handed to the browser.
  ///
  /// Matched on the origin and a whole path segment, not a prefix: a prefix
  /// test would treat `https://termphin.dev.example.com` as ours and keep a
  /// page we do not control inside a view the user reads as part of the app.
  /// The rest of termphin.dev is the landing site and goes to the browser.
  static bool isManual(Uri url) {
    final home = Uri.parse(ManualUrls.home);
    if (url.scheme != home.scheme) return false;
    if (url.host == _legacyHost) return true;
    return url.host == home.host &&
        (url.path == home.path || url.path.startsWith('${home.path}/'));
  }
}

/// A page of the manual the app links to, with the heading to land on.
///
/// Closed so `manual_pages_test.dart` can check every one against the
/// manual's sources: a page renamed or a heading reworded there fails the
/// test instead of dropping the user on a 404 or the top of a long page.
/// Anchors are the ids the site derives from each heading's text.
enum ManualPage {
  home(''),
  cloudServer('getting-started/no-server', 'a-cloud-server-vps'),
  enableSsh('ssh/enable-ssh'),
  hostKeys('connections/host-keys'),
  remoteAgent('sessions/remote-agent'),
  troubleshooting('help/troubleshooting'),
  hostUnreachable(
    'help/troubleshooting',
    'the-server-did-not-answer-check-the-address-and-port',
  ),
  wrongPassword('help/troubleshooting', 'wrong-username-or-password'),
  keyRefused(
    'help/troubleshooting',
    'the-server-did-not-accept-this-key-check-the-username-and-that-the-key-is-authorised-on-the-server',
  ),
  keyUnreadable(
    'help/troubleshooting',
    'wrong-passphrase-for-this-key--this-key-could-not-be-read--this-profiles-key-is-gone-from-the-key-manager',
  ),
  hostKeyChanged(
    'help/troubleshooting',
    'this-servers-key-has-changed-remove-the-old-one-in-settings--known-hosts-if-that-was-expected',
  ),
  hostKeyRejected(
    'help/troubleshooting',
    'you-did-not-accept-the-servers-key-nothing-was-sent',
  ),
  localNetworkBlocked(
    'help/troubleshooting',
    'this-machine-is-on-the-network-youre-connected-to-which-termphin-doesnt-have-permission-to-reach-yet',
  ),
  localNetworkUnverified(
    'help/troubleshooting',
    'nothing-answered-at-this-address-it-is-on-the-network-youre-connected-to-so-either-the-machine-is-off-or-termphin-does-not-have-permission-to-reach-it',
  ),
  jumpHost(
    'help/troubleshooting',
    'the-jump-host-connection-failed--this-profiles-jump-host-is-not-set-up-right',
  );

  const ManualPage(this.path, [this.anchor]);

  /// Relative to [ManualUrls.home]; empty for the manual's front page.
  final String path;
  final String? anchor;

  Uri get url {
    final page = path.isEmpty ? ManualUrls.home : '${ManualUrls.home}/$path';
    return Uri.parse(anchor == null ? page : '$page#$anchor');
  }
}
