import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Decoded unsubscribe request.
typedef UnsubscribePayload = ({String accountId, String scope});

/// Stateless, signed one-click unsubscribe tokens (no DB row per email).
///
/// Format: `base64url(accountId|scope).base64url(hmacSha256(secret, body))`.
/// The token is opaque (no readable PII beyond the account id, which is already
/// an opaque key) and self-validating.
class UnsubscribeToken {
  const UnsubscribeToken(this._secret);

  final String _secret;

  /// `scope` is a category name or `all`.
  String sign({required String accountId, required String scope}) {
    final body = '$accountId|$scope';
    final bodyB64 = base64Url.encode(utf8.encode(body));
    return '$bodyB64.${_mac(bodyB64)}';
  }

  /// Returns the payload when the signature is valid, else null.
  UnsubscribePayload? verify(String token) {
    final dot = token.indexOf('.');
    if (dot <= 0 || dot == token.length - 1) {
      return null;
    }
    final bodyB64 = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    if (!_constantTimeEquals(sig, _mac(bodyB64))) {
      return null;
    }
    final String body;
    try {
      body = utf8.decode(base64Url.decode(bodyB64));
    } on FormatException {
      return null;
    }
    final sep = body.indexOf('|');
    if (sep <= 0) {
      return null;
    }
    return (
      accountId: body.substring(0, sep),
      scope: body.substring(sep + 1),
    );
  }

  String _mac(String bodyB64) {
    final mac = Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode(bodyB64));
    return base64Url.encode(mac.bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
