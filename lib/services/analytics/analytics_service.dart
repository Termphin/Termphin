import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_config.dart';

const kAnalyticsConsentPrefsKey = 'analytics_consent';

/// The only events this app ever sends. Deliberately an enum rather than a
/// free-form string - PostHog auto-captures nothing (no autocapture, no
/// `$screen`, no lifecycle events), so this list is the entire event catalog.
///
/// It is also what the privacy policy's event table is written from, so a name
/// added here without being added there makes the policy wrong.
enum AnalyticsEvent {
  appOpened('app_opened'),

  /// Sent by hand from the places that switch screens, not by PostHog's
  /// `$screen` autocapture, which stays off: the four main destinations are
  /// tabs in one Stack rather than routes, so a navigator observer would miss
  /// them and a mounted-widget hook would report all four at once.
  screenViewed('screen_viewed'),
  settingChanged('setting_changed'),

  /// The activation step. Without it there is no way to tell someone who
  /// installed the app and bounced off an empty list from someone who set a
  /// server up and then could not reach it.
  profileCreated('profile_created'),
  connectionSuccess('connection_success'),
  connectionFailed('connection_failed'),

  /// A connection that was established and then died on its own, which is a
  /// different failure from one that never came up.
  connectionDropped('connection_dropped'),
  sessionResumed('session_resumed'),

  /// Play never reports whether its dialog appeared, let alone what was
  /// rated - that the ask was made is the only measurable part.
  reviewPromptRequested('review_prompt_requested'),
  reviewStoreOpened('review_store_opened');

  const AnalyticsEvent(this.eventName);
  final String eventName;
}

/// The complete vocabulary of property names, closed for the same reason
/// [AnalyticsEvent] is: what is sent has to be readable off one list, both to
/// keep the privacy policy honest and to keep a hostname or a path from ever
/// being handed to [AnalyticsService.capture] under an ad-hoc key.
enum AnalyticsProperty {
  screen('screen'),
  setting('setting'),
  value('value'),
  reason('reason'),
  authMethod('auth_method'),
  multiplexer('multiplexer'),
  viaJumpHost('via_jump_host'),
  usedFallback('used_fallback'),
  fallbackCount('fallback_count'),
  portForwards('port_forwards'),
  retry('retry'),

  /// How long the attempt took, in milliseconds. A first connect to a machine
  /// uploads the agent and a later one does not, so without this the two are
  /// one number and there is no way to tell a slow host from a slow install.
  durationMs('duration_ms'),
  agentInstalled('agent_installed'),

  /// How a lost connection was noticed: the keepalive's silence limit, a probe
  /// after a network change or a resume, or the transport closing on its own.
  lostVia('lost_via'),

  /// From a drop being noticed to the session being back, in milliseconds.
  downtimeMs('downtime_ms'),

  /// Whether a reconnect continued the terminal on screen instead of replaying
  /// the session's history into a new one.
  inPlace('in_place');

  const AnalyticsProperty(this.propertyName);
  final String propertyName;
}

/// Screens, as analytics sees them. Names are ours, not widget class names,
/// so renaming a class does not silently split a funnel in two.
enum AnalyticsScreen {
  home('home'),
  snippets('snippets'),
  snippetRuns('snippet_runs'),
  keyManager('key_manager'),
  settings('settings'),
  terminal('terminal'),
  lock('lock'),
  terminalAppearance('terminal_appearance'),
  toolbarSettings('toolbar_settings'),
  actionDockSettings('action_dock_settings'),
  fastUploadSettings('fast_upload_settings'),
  knownHosts('known_hosts'),
  releaseNotes('release_notes'),
  export('export'),
  sftpEditor('sftp_editor'),
  editorSettings('editor_settings'),
  sftpImagePreview('sftp_image_preview'),
  manual('manual'),

  /// The new or edit machine form, so an abandoned first profile is visible
  /// next to the ones that got saved.
  profileForm('profile_form'),
  serverGuide('server_guide');

  const AnalyticsScreen(this.screenName);
  final String screenName;
}

/// Strips `$ip` from event properties before they leave the device.
///
/// Belt and suspenders: the native SDKs resolve `$ip` server-side from the
/// request, after this callback runs, so it is never actually present here.
/// The setting that matters is the PostHog project's own "Discard client IP
/// data" toggle (Project Settings > General) - this cannot reach that from
/// the client.
PostHogEvent _stripIp(PostHogEvent event) {
  event.properties?.remove(r'$ip');
  event.properties?.remove('ip');
  return event;
}

/// Whether an `$exception` payload is nothing but a transport closing.
///
/// A dropped SSH socket is this app's ordinary weather, and the message carries
/// the address and port of the machine the user reached, which must not leave
/// the device.
@visibleForTesting
bool isTransportOnlyException(Map<String, Object?> properties) {
  final exceptionList = properties[r'$exception_list'];
  if (exceptionList is! List || exceptionList.isEmpty) {
    return false;
  }
  for (final item in exceptionList) {
    if (item is! Map) {
      return false;
    }
    final type = item['type'];
    final value = item['value'];
    final isSocketType = type == 'SocketException';
    final isSocketValue =
        value is String && value.startsWith('SocketException');
    if (!isSocketType && !isSocketValue) {
      return false;
    }
  }
  return true;
}

PostHogEvent? _dropTransportNoise(PostHogEvent event) {
  if (event.event == r'$exception' &&
      isTransportOnlyException(event.properties ?? const {})) {
    return null;
  }
  return event;
}

/// Gates PostHog behind explicit consent.
///
/// [init] always calls `Posthog().setup()` so the SDK is ready, but starts it
/// opted out unless a previous run already recorded consent - nothing is
/// captured before the user has answered the prompt, or after they turn it
/// off in Settings. Every autocapture surface (app lifecycle events, screen
/// views, rage clicks, push events, feature flags, session replay, surveys)
/// is off - only the events in [AnalyticsEvent], captured explicitly through
/// [capture], ever leave the device.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  /// Whether the user has been asked and, if so, what they answered. Null
  /// means the prompt has never been shown.
  Future<bool?> loadConsent() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(kAnalyticsConsentPrefsKey);
  }

  /// Whether `Posthog().setup()` has run in this process.
  bool _started = false;

  /// This is a singleton, so a test that starts the SDK would otherwise leave
  /// it started for every test after it.
  @visibleForTesting
  void resetForTest() => _started = false;

  /// Brings the SDK up, which happens only once consent is on record.
  ///
  /// `setup()` generates a device id and writes it to the phone, and no config
  /// option prevents that - `optOut` only gates sending. Storing an identifier
  /// on someone's device is the thing ePrivacy Art. 5(3) asks consent for, so
  /// the SDK is not touched at all until the answer is yes.
  ///
  /// No autocapture: this app's only events are the ones in [AnalyticsEvent],
  /// captured explicitly.
  Future<void> _start() async {
    final config = PostHogConfig(AnalyticsConfig.projectApiKey)
      ..host = AnalyticsConfig.host
      ..captureApplicationLifecycleEvents = false
      ..preloadFeatureFlags = false
      ..sendFeatureFlagEvents = false
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..surveys = false
      ..sessionReplay = false
      ..beforeSend = [_stripIp, _dropTransportNoise]
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true;

    config.rageClickConfig.enabled = false;
    await Posthog().setup(config);
    _started = true;
  }

  Future<void> init() async {
    if (!AnalyticsConfig.isConfigured) return;
    if (await loadConsent() != true) return;
    await _start();
  }

  /// Records the user's choice and acts on it immediately - from the initial
  /// prompt, or later from Settings.
  ///
  /// The first yes is also what starts the SDK, since [init] leaves it alone
  /// until then. The `app_opened` for that launch is already gone by this
  /// point; counting it would mean capturing before the answer.
  Future<void> setConsent(bool granted) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(kAnalyticsConsentPrefsKey, granted);
    if (!AnalyticsConfig.isConfigured) return;
    if (granted) {
      if (!_started) await _start();
      await Posthog().enable();
    } else if (_started) {
      await Posthog().disable();
    }
  }

  /// Captures [event]. A no-op until consent has started the SDK, so callers
  /// never need to check consent first. Callers fire this and forget it, so a
  /// failure (no network, platform channel unavailable in a test) is swallowed
  /// rather than surfacing somewhere unrelated.
  ///
  /// [properties] carries dimensions, never content: an enum name, a flag or
  /// a count. Nothing derived from a host, a username, a path, a command or
  /// an error message goes in one - see [_assertSafe] for the tripwire that
  /// catches the obvious shapes of that in debug.
  Future<void> capture(
    AnalyticsEvent event, {
    Map<AnalyticsProperty, Object>? properties,
  }) async {
    if (!AnalyticsConfig.isConfigured || !_started) return;
    assert(_assertSafe(properties));
    try {
      await Posthog().capture(
        eventName: event.eventName,
        properties: properties?.map(
          (property, value) => MapEntry(property.propertyName, value),
        ),
      );
    } catch (_) {}
  }

  /// Records that [screen] came to the front.
  Future<void> screen(AnalyticsScreen screen) => capture(
    AnalyticsEvent.screenViewed,
    properties: {AnalyticsProperty.screen: screen.screenName},
  );

  /// Records that a persisted preference was written. Called from
  /// `Setting.set`, so no individual settings screen has to remember to.
  ///
  /// [value] is null for settings whose value is not a single scalar - a
  /// toolbar layout, a list of custom keys - where the count or nothing at
  /// all is all that can be said without shipping what the user typed.
  Future<void> settingChanged(String key, Object? value) => capture(
    AnalyticsEvent.settingChanged,
    properties: {
      AnalyticsProperty.setting: key,
      AnalyticsProperty.value: ?value,
    },
  );

  /// Debug-only shape check on property values.
  ///
  /// Not a proof that nothing sensitive is being sent - only the call sites
  /// can be that - but every string that would carry an address, a path or a
  /// user account has one of these characters in it, so a mistake of that
  /// kind trips here instead of shipping.
  bool _assertSafe(Map<AnalyticsProperty, Object>? properties) {
    if (properties == null) return true;
    for (final entry in properties.entries) {
      final value = entry.value;
      if (value is bool || value is num) continue;
      if (value is String &&
          value.length <= 64 &&
          !value.contains(RegExp(r'[@/\\\n\r]'))) {
        continue;
      }
      debugPrint('Analytics: unsafe value for ${entry.key.propertyName}');
      return false;
    }
    return true;
  }
}
