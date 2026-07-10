import 'package:flutter/foundation.dart';

import 'package:tentura/consts.dart';

const _kEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

/// Whether Flutter Web enables the semantics tree at startup.
///
/// Off in release and when `ENV=prod` so the `flt-semantics-host` overlay does
/// not swallow pointer events meant for platform views (e.g. Google Maps).
bool get kEnableWebSemantics =>
    kIsWeb && !kReleaseMode && _kEnv != 'prod';

bool _isAbsoluteHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
  return uri.scheme == 'http' || uri.scheme == 'https';
}

/// Fail fast on web when compile-time URL defines are missing or invalid.
void assertWebBuildConfig() {
  if (!kIsWeb || _kEnv == 'test') return;

  final missing = <String>[];
  if (!_isAbsoluteHttpUrl(kServerName)) missing.add('SERVER_NAME');
  if (!_isAbsoluteHttpUrl(kImageServer)) missing.add('IMAGE_SERVER');

  if (missing.isEmpty) return;

  throw StateError(
    'Web build misconfigured: set ${missing.join(', ')} via '
    '--dart-define or --dart-define-from-file. '
    'Local dev: copy .env.example to .env, then run '
    './scripts/run-flutter-web-local.sh',
  );
}
