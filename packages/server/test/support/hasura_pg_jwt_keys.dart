import 'dart:io';

import 'package:tentura_server/env.dart';

/// Shared JWT PEM loader for isolated Hasura pg tests (tentura-50o).
///
/// Resolution order: repo `.env` entries, then process environment, then
/// [Env.kJwtPublicKey] / [Env.kJwtPrivateKey] (CI and fresh checkout).
({String publicKey, String privateKey}) loadJwtKeysForHasuraPgTests({
  File? repoDotEnvOverride,
  Map<String, String>? platformEnvironmentOverride,
}) {
  final platformEnv = platformEnvironmentOverride ?? Platform.environment;
  final dotEnv =
      repoDotEnvOverride ?? File('${Directory.current.path}/../../.env');

  final values = <String, String>{};
  if (dotEnv.existsSync()) {
    for (final line in dotEnv.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      values[trimmed.substring(0, idx)] = trimmed
          .substring(idx + 1)
          .replaceAll(r'\n', '\n');
    }
  }

  final publicKey =
      values['JWT_PUBLIC_PEM'] ??
      platformEnv['JWT_PUBLIC_PEM'] ??
      Env.kJwtPublicKey.replaceAll(r'\n', '\n');
  final privateKey =
      values['JWT_PRIVATE_PEM'] ??
      platformEnv['JWT_PRIVATE_PEM'] ??
      Env.kJwtPrivateKey.replaceAll(r'\n', '\n');

  return (publicKey: publicKey, privateKey: privateKey);
}
