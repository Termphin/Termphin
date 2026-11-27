/// Where someone was when Pro was put in front of them: what the paywall
/// and the Pro hints report as [AnalyticsProperty.source], so the funnel
/// shows which moments sell and which only annoy.
enum ProSource {
  account('account'),
  settingsNotifications('settings_notifications'),
  syncCard('sync_card'),
  liveStatus('live_status'),
  longCommandHint('long_command_hint'),
  settings('settings'),
  whatsNew('whats_new');

  const ProSource(this.id);

  final String id;
}
