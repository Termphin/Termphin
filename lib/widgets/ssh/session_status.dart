import 'package:flutter/widgets.dart';

import '../../i18n/strings.g.dart';
import '../../models/active_session.dart';
import '../../models/session_tab.dart';
import '../../services/app/identity_anonymizer.dart';
import '../../theme/theme.dart';

/// How a session tab reads wherever it is listed: green when connected, the
/// accent while the handshake is in flight, amber when its remote session is
/// only detached (alive on the server, nothing connected here), and dim for a
/// dropped plain-SSH tab with nothing on the server to pick back up.
class SessionStatus {
  SessionStatus.of(ActiveSessionView session, Translations t, AppColors colors)
    : connecting = session.connecting && !session.dropped,
      connected = !session.dropped && !session.connecting,
      resumable = session.multiplexer.isPersistent,
      _uptime = session.uptimeFormatted,
      _t = t,
      _colors = colors;

  final bool connecting;
  final bool connected;

  /// The agent backend is what "detached" actually describes; a plain SSH
  /// tab that died has nothing waiting for it.
  final bool resumable;

  final String _uptime;
  final Translations _t;
  final AppColors _colors;

  Color get color => connecting
      ? _colors.primary
      : connected
      ? _colors.success
      : resumable
      ? _colors.warning
      : _colors.textTertiary;

  String get label => connecting
      ? _t.connection.connecting
      : connected
      ? _uptime
      : resumable
      ? _t.session.detached
      : _t.connection.disconnected;
}

/// A session by its own name, or by where it connects when it has none.
String sessionDisplayName(
  ActiveSessionView session, {
  required bool anonymize,
}) {
  final muxName = session.muxName;
  if (muxName != null) return SessionTab.displayName(muxName);
  final profile = session.profile;
  return anonymize
      ? '${IdentityAnonymizer.username(profile.id)}@'
            '${IdentityAnonymizer.host(profile.id)}'
      : '${profile.username}@${profile.host}';
}
