import 'dart:math' as math;

/// A secret detection rule with an optional keyword pre-filter and
/// contextual entropy gate, inspired by Gitleaks and detect-secrets.
class SecretRule {
  const SecretRule({
    required this.id,
    required this.pattern,
    this.groups = const [0],
    this.keywords = const [],
    this.minEntropy,
    this.allow,
  });

  /// Short identifier for diagnostics and tests.
  final String id;

  /// Pattern matching the secret or its surrounding assignment.
  final RegExp pattern;

  /// Capture group indices checked in order for the secret payload.
  final List<int> groups;

  /// Lowercase substrings; when non-empty, [pattern] runs only if at least
  /// one keyword appears in the text.
  final List<String> keywords;

  /// Minimum Shannon entropy (bits per character) required to redact.
  final double? minEntropy;

  /// Returns true when a candidate value is harmless and should stay visible.
  final bool Function(String value)? allow;

  /// Extracts the secret payload from [match], or null if no group matched.
  String? extractSecret(Match match) {
    for (final index in groups) {
      final value = match.group(index);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Whether [lowerText] contains any pre-filter keyword for this rule.
  bool matchesKeywords(String lowerText) =>
      keywords.isEmpty || keywords.any(lowerText.contains);
}

/// Shannon entropy in bits per character for [value], used to tell real
/// random tokens apart from readable config words.
double shannonEntropy(String value) {
  if (value.isEmpty) return 0;
  final counts = <int, int>{};
  for (final unit in value.codeUnits) {
    counts[unit] = (counts[unit] ?? 0) + 1;
  }
  final length = value.length;
  var entropy = 0.0;
  for (final count in counts.values) {
    final p = count / length;
    entropy -= p * (math.log(p) / math.ln2);
  }
  return entropy;
}

bool _isTemplateOrNonSecretLiteral(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith(r'$') ||
      (trimmed.startsWith('<') && trimmed.endsWith('>')) ||
      (trimmed.startsWith('{{') && trimmed.endsWith('}}'))) {
    return true;
  }
  return _nonSecretLiterals.contains(trimmed.toLowerCase());
}

bool _isHarmlessGenericValue(String value) {
  if (_isTemplateOrNonSecretLiteral(value)) return true;
  final trimmed = value.trim();
  if (trimmed.startsWith('/') ||
      trimmed.startsWith('./') ||
      trimmed.startsWith('~/')) {
    return true;
  }
  if ((trimmed.startsWith('http://') || trimmed.startsWith('https://')) &&
      !trimmed.contains('@') &&
      !trimmed.contains('?')) {
    return true;
  }
  if (_plainIdentifier.hasMatch(trimmed)) return true;
  final lower = trimmed.toLowerCase();
  return lower.startsWith('ssh-rsa') ||
      lower.startsWith('ssh-ed25519') ||
      lower.startsWith('ecdsa-sha2-');
}

final _plainIdentifier = RegExp(r'^[a-z]+(?:[_-][a-z0-9]+)+$');

const _nonSecretLiterals = {
  'true',
  'false',
  'null',
  'none',
  'undefined',
  'empty',
  'changeme',
  'placeholder',
  'example',
  'redacted',
  'disabled',
  'enabled',
};

/// Secret patterns ordered from multi-line blocks and structured assignments
/// down to provider-prefixed tokens.
final List<SecretRule> assistantSecretRules = [
  SecretRule(
    id: 'private-key',
    keywords: const ['private key'],
    pattern: RegExp(
      r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY[A-Z0-9 ]*-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY[A-Z0-9 ]*-----',
    ),
  ),
  SecretRule(
    id: 'url-credentials',
    keywords: const ['://'],
    groups: const [1],
    pattern: RegExp(r'\b[a-z][a-z0-9+.-]*://[^\s:/@]+:([^\s@/]+)@'),
  ),
  SecretRule(
    id: 'credential-assignment',
    groups: const [1, 2, 3],
    allow: _isTemplateOrNonSecretLiteral,
    pattern: RegExp(
      r'''\b[A-Za-z0-9_]*(?:PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|AUTH_?KEY|CREDENTIALS?)[A-Za-z0-9_]*["']?\s*[=:]\s*(?:"([^"\r\n]{4,})"|'([^'\r\n]{4,})'|([^\s"'`;,\r\n]{4,}))''',
      caseSensitive: false,
    ),
  ),
  SecretRule(
    id: 'generic-high-entropy-assignment',
    groups: const [1, 2, 3],
    minEntropy: 3.6,
    allow: _isHarmlessGenericValue,
    pattern: RegExp(
      r'''\b[A-Za-z0-9_]*(?:KEY|PASS|PWD|AUTH|SALT|SIGNING|SIGNATURE|HMAC|WEBHOOK|DSN|COOKIE|SESSION|OAUTH|PRIVATE)(?!(?:_?(?:DOMAIN|HOST|PORT|DRIVER|TYPE|MODE|PATH|FILE|DIR|ENABLED|TIMEOUT|TTL|ALGO|FORMAT|NAME|PREFIX|HEADER|SCHEME|METHOD))\b)[A-Za-z0-9_]*["']?\s*[=:]\s*(?:"([^"\r\n]{12,})"|'([^'\r\n]{12,})'|([^\s"'`;,\r\n]{12,}))''',
      caseSensitive: false,
    ),
  ),
  SecretRule(
    id: 'bearer-or-basic-auth',
    keywords: const ['bearer ', 'basic '],
    groups: const [1],
    pattern: RegExp(r'\b(?:[Bb]earer|[Bb]asic)\s+([A-Za-z0-9._~+/=-]{12,})'),
  ),
  SecretRule(
    id: 'aws-access-key',
    keywords: const ['a3t', 'akia', 'asia', 'abia', 'acca'],
    pattern: RegExp(r'\b(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b'),
  ),
  SecretRule(
    id: 'github-token',
    keywords: const ['ghp_', 'gho_', 'ghu_', 'ghs_', 'ghr_', 'github_pat_'],
    pattern: RegExp(
      r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b',
    ),
  ),
  SecretRule(
    id: 'gitlab-token',
    keywords: const ['glpat-', 'glrt-', 'gldt-'],
    pattern: RegExp(
      r'\b(?:glpat-[A-Za-z0-9_-]{20,}(?:\.[A-Za-z0-9_-]{10,})?|gl[rd]t-[A-Za-z0-9_-]{20,})\b',
    ),
  ),
  SecretRule(
    id: 'stripe-key',
    keywords: const ['_live_', '_test_', '_prod_'],
    pattern: RegExp(r'\b(?:sk|rk|pk)_(?:live|test|prod)_[A-Za-z0-9]{16,}\b'),
  ),
  SecretRule(
    id: 'slack-token',
    keywords: const ['xox'],
    pattern: RegExp(r'\bxox[abceoprs]-[A-Za-z0-9-]{10,}\b'),
  ),
  SecretRule(
    id: 'slack-webhook',
    keywords: const ['hooks.slack.com'],
    pattern: RegExp(
      r'https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+',
    ),
  ),
  SecretRule(
    id: 'discord-webhook',
    keywords: const ['discord.com/api/webhooks', 'discordapp.com/api/webhooks'],
    pattern: RegExp(
      r'https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_-]{20,}',
    ),
  ),
  SecretRule(
    id: 'sk-api-key',
    keywords: const ['sk-'],
    pattern: RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
  ),
  SecretRule(
    id: 'google-api-key',
    keywords: const ['aiza'],
    pattern: RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b'),
  ),
  SecretRule(
    id: 'google-oauth-token',
    keywords: const ['ya29.'],
    pattern: RegExp(r'\bya29\.[0-9A-Za-z_-]{20,}\b'),
  ),
  SecretRule(
    id: 'npm-token',
    keywords: const ['npm_'],
    pattern: RegExp(r'\bnpm_[A-Za-z0-9]{30,}\b'),
  ),
  SecretRule(
    id: 'pypi-token',
    keywords: const ['pypi-ageichlwas5vcmc'],
    pattern: RegExp(r'\bpypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{20,}\b'),
  ),
  SecretRule(
    id: 'sendgrid-key',
    keywords: const ['sg.'],
    pattern: RegExp(r'\bSG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b'),
  ),
  SecretRule(
    id: 'digitalocean-token',
    keywords: const ['dop_v1_', 'doo_v1_', 'dor_v1_'],
    pattern: RegExp(r'\bdo[por]_v1_[a-f0-9]{64}\b'),
  ),
  SecretRule(
    id: 'hashicorp-vault-token',
    keywords: const ['hvs.', 'hvb.'],
    pattern: RegExp(r'\bhv[bs]\.[A-Za-z0-9_-]{20,}\b'),
  ),
  SecretRule(
    id: 'huggingface-token',
    keywords: const ['hf_'],
    pattern: RegExp(r'\bhf_[A-Za-z0-9]{20,}\b'),
  ),
  SecretRule(
    id: 'telegram-bot-token',
    keywords: const [':aa'],
    pattern: RegExp(r'\b\d{8,12}:AA[A-Za-z0-9_-]{30,}\b'),
  ),
  SecretRule(
    id: 'mailgun-key',
    keywords: const ['key-'],
    minEntropy: 3.2,
    pattern: RegExp(r'\bkey-[a-f0-9]{32}\b'),
  ),
  SecretRule(
    id: 'databricks-token',
    keywords: const ['dapi'],
    pattern: RegExp(r'\bdapi[a-f0-9]{32}(?:-\d)?\b'),
  ),
  SecretRule(
    id: 'grafana-token',
    keywords: const ['glc_', 'glsa_'],
    pattern: RegExp(
      r'\b(?:glc_[A-Za-z0-9+/=_-]{20,}|glsa_[A-Za-z0-9_]{20,})\b',
    ),
  ),
  SecretRule(
    id: 'shopify-token',
    keywords: const ['shpat_', 'shpca_', 'shppa_', 'shpss_'],
    pattern: RegExp(r'\bshp(?:at|ca|pa|ss)_[a-fA-F0-9]{32}\b'),
  ),
  SecretRule(
    id: 'linear-key',
    keywords: const ['lin_api_'],
    pattern: RegExp(r'\blin_api_[A-Za-z0-9]{32,}\b'),
  ),
  SecretRule(
    id: 'supabase-secret-key',
    keywords: const ['sb_secret_'],
    pattern: RegExp(r'\bsb_secret_[A-Za-z0-9_-]{20,}\b'),
  ),
  SecretRule(
    id: 'age-secret-key',
    keywords: const ['age-secret-key-'],
    pattern: RegExp(
      r'\bAGE-SECRET-KEY-1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{58}\b',
    ),
  ),
  SecretRule(
    id: 'jwt',
    keywords: const ['eyj'],
    pattern: RegExp(
      r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
    ),
  ),
];
