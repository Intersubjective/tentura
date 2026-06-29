import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:tentura_server/env.dart';

/// Opaque, stable node identity for invite-genealogy graph edges.
///
/// Derived from the user id and a server-only secret so graph node ids never
/// expose live `U…` account ids.
abstract final class InviteGenealogyNodeKey {
  static String derive({required String userId, required Env env}) {
    final secret = _secret(env);
    final mac = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(userId));
    return 'G${base64Url.encode(mac.bytes).replaceAll('=', '')}';
  }

  static String _secret(Env env) {
    if (env.genealogyNodeKeySecret.isNotEmpty) {
      return env.genealogyNodeKeySecret;
    }
    if (env.unsubscribeSigningSecret.isNotEmpty) {
      return env.unsubscribeSigningSecret;
    }
    return 'dev-genealogy-node-key-secret';
  }
}
