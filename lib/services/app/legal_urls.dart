/// Where the published legal documents live.
///
/// The source of truth is `docs/legal/*.md`, which the landing site renders
/// into these pages at build time. The app links out rather than bundling a
/// copy - Play requires a public URL anyway, and one that cannot drift from
/// what the app shows is worth more than reading it offline.
class LegalUrls {
  const LegalUrls._();

  static const privacyPolicy = 'https://termphin.dev/privacy';
  static const termsOfService = 'https://termphin.dev/terms';
}
