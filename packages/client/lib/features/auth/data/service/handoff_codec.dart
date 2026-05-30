import 'dart:convert';

import 'handoff_payload.dart';

// HANDOFF-CONTRACT-PIN (keep in sync with packages/landing/handoff.js and
// docs/handoff-contract.md — enforced by scripts/check_handoff_contract.sh):
//   key=th v userId seed displayName
const handoffFragmentKey = 'th';
const _supportedVersion = 1;

///
/// Decodes a raw URL fragment (`#th=<base64url(utf8(json))>`, or the same
/// without the leading `#`) into a [HandoffPayload].
///
/// Returns `null` when there is no handoff parameter, the version is
/// unsupported, or the payload is malformed — callers fall through to the
/// normal auth path. Pure (no platform deps) so it is unit-testable on the VM.
///
HandoffPayload? decodeHandoffFragment(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  final fragment = raw.startsWith('#') ? raw.substring(1) : raw;
  String? encoded;
  for (final part in fragment.split('&')) {
    final eq = part.indexOf('=');
    if (eq > 0 && part.substring(0, eq) == handoffFragmentKey) {
      encoded = part.substring(eq + 1);
      break;
    }
  }
  if (encoded == null || encoded.isEmpty) return null;

  try {
    final json =
        jsonDecode(utf8.decode(base64Url.decode(base64.normalize(encoded))))
            as Map<String, dynamic>;
    if (json['v'] != _supportedVersion) return null;

    final userId = json['userId'] as String?;
    final seed = json['seed'] as String?;
    if (userId == null || userId.isEmpty || seed == null || seed.isEmpty) {
      return null;
    }
    return HandoffPayload(
      userId: userId,
      seed: seed,
      displayName: json['displayName'] as String?,
    );
  } catch (_) {
    return null;
  }
}
