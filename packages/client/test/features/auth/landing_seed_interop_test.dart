import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

// Pins the cross-language contract between the static landing's WebCrypto
// Ed25519 signup (packages/landing/auth.js) and the Dart app/server.
//
// These vectors were produced by the *browser* path: WebCrypto
// `generateKey({name:'Ed25519'})` -> seed = trailing 32 bytes of the PKCS#8
// export (url-safe base64 WITH padding), pk = raw public key (url-safe base64),
// and a self-signed EdDSA auth-request JWT over the `pk` claim.
//
// The risk this guards: if the landing's seed string and the app's
// `newKeyFromSeed(base64Decode(seed))` (auth_box.dart) ever diverge by one byte,
// signup *succeeds* on the landing but `signIn` silently finds no matching
// `ed25519_device` credential in the app. No JS-side test exists, so this pins
// the Dart half of the contract — especially the padding-sensitive decode.
const _seedB64 = 'kwG5tM4qMzTI-7ItZK-xMlIdTkVEmQcnkOJ6pSFX40w=';
const _pkB64 = 'uxzEXeX_i2v-VR6cFUp707RGtB3OI92vae2moEiUOv0=';
const _authRequestToken =
    'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.'
    'eyJpbnQiOiJzaWduX3VwIiwicGsiOiJ1eHpFWGVYX2kydi1WUjZjRlVwNzA3Ukd0QjNPSTkydmFlMm1vRWlVT3YwPSJ9.'
    'C7gRFw2vYPnmOMF6fi4mgFqeYaUr1mRZJcgSPEdzTPv8-qjUyG3XEjxcMYvPevpueCB7OaOrfFqL0nhZnXygAQ';

void main() {
  group('landing WebCrypto seed interop', () {
    test('app derives the same public key from the landing seed', () {
      // Mirrors AuthBox.fromSeed (auth_box.dart:34).
      final priv = newKeyFromSeed(base64Decode(_seedB64));
      final derivedPk = base64UrlEncode(public(priv).bytes);
      expect(derivedPk, _pkB64);
    });

    test('the seed string requires padding (un-padded throws)', () {
      // Documents why auth.js must emit a PADDED seed: the app uses base64Decode
      // (no base64.normalize), which rejects un-padded input.
      final unpadded = _seedB64.replaceAll('=', '');
      expect(() => base64Decode(unpadded), throwsFormatException);
    });

    test('auth-request JWT verifies via the server _verifyAuthRequest path', () {
      // Mirrors AuthCase._verifyAuthRequest (auth_case.dart:153).
      final decoded = JWT.decode(_authRequestToken);
      expect(decoded.header?['alg'], 'EdDSA');

      final pk = (decoded.payload as Map)['pk'] as String;
      final verified = JWT.verify(
        _authRequestToken,
        EdDSAPublicKey(base64Decode(base64.normalize(pk))),
      );
      expect((verified.payload as Map)['pk'], _pkB64);
    });
  });
}
