import 'package:flutter/foundation.dart';

import 'package:tentura/consts.dart';

const _kEnv = String.fromEnvironment('ENV');

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

  final inviteBase = resolveInviteLinkHost(
    inviteLinkHost: kInviteLinkHost,
    serverName: kServerName,
  );
  if (!_isAbsoluteHttpUrl(inviteBase)) {
    missing.add('INVITE_LINK_HOST (or derivable SERVER_NAME)');
  }

  if (missing.isEmpty) return;

  throw StateError(
    'Web build misconfigured: set ${missing.join(', ')} via '
    '--dart-define or --dart-define-from-file. '
    'Local dev: copy .env.example to .env, then run '
    './scripts/run-flutter-web-local.sh',
  );
}
