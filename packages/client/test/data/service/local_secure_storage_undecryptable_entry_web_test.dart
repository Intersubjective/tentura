// Run with: flutter test --platform chrome <this file>
//
// Real web secure storage (flutter_secure_storage_web over localStorage and
// WebCrypto). An entry encrypted under a different AES key — what happens
// when two tabs each generate their own key — makes WebCrypto reject with a
// DOMException 'OperationError'. Reading around it must complete without an
// error, readable entries must still be returned, and the undecryptable
// ciphertext must stay in localStorage byte-for-byte.
@TestOn('browser')
@Timeout(Duration(seconds: 60))
library;

// `flutter test --platform chrome` does not run the web plugin registrant;
// register the real web implementation the app uses. It is a transitive
// dependency of flutter_secure_storage.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
// SDK package that is not listed in pubspec; only its registrar is needed.
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'package:tentura/data/service/local_secure_storage.dart';

import '../../support/browser/foreign_key_secure_storage.dart';

const _readableAccountKey = 'Auth:Id:Ureadable01';
const _brokenAccountKey = 'Auth:Id:Ubroken0002';

void main() {
  setUpAll(() => FlutterSecureStorageWeb.registerWith(webPluginRegistrar));
  setUp(clearSecureStorageItems);
  tearDown(clearSecureStorageItems);

  group('web secure storage with an entry encrypted under another key', () {
    late String brokenCiphertext;

    setUp(() async {
      await LocalSecureStorage().write(_readableAccountKey, 'seed-readable');
      brokenCiphertext = (await writeUnderForeignKey({
        _brokenAccountKey: 'seed-broken',
      }))[_brokenAccountKey]!;
      // Precondition: the own key still decrypts the readable entry.
      expect(
        await LocalSecureStorage().read(_readableAccountKey),
        'seed-readable',
      );
    });

    test('read of the undecryptable entry completes with null', () async {
      await expectLater(
        LocalSecureStorage().read(_brokenAccountKey),
        completion(isNull),
      );
    });

    test(
      'readAll completes with the readable entries and without the '
      'undecryptable one',
      () async {
        await expectLater(
          LocalSecureStorage().readAll(),
          completion(
            allOf(
              containsPair(_readableAccountKey, 'seed-readable'),
              isNot(contains(_brokenAccountKey)),
            ),
          ),
        );
      },
    );

    test(
      'the undecryptable ciphertext stays in localStorage unchanged after '
      'read and readAll',
      () async {
        final storage = LocalSecureStorage();

        await expectLater(storage.read(_brokenAccountKey), completes);
        await expectLater(storage.readAll(), completes);

        expect(
          rawSecureStorageItem(_brokenAccountKey),
          brokenCiphertext,
          reason: 'seeds that fail to decrypt are never deleted or rewritten',
        );
      },
    );
  });
}
