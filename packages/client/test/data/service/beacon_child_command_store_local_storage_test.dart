// The Request-creation client command id is not a secret: it lives in
// ordinary local storage (shared_preferences — localStorage on web), not in
// the encrypted secure storage, so an undecryptable secure-storage entry can
// never break Request creation. The keys stay the same; values already in
// secure storage are not migrated.
//
// Contract: the store is built without the secure storage
// (`BeaconChildCommandStore()`), and reaches shared_preferences itself.
import 'dart:collection';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive (federated) interface of shared_preferences; only its in-memory
// test backend for SharedPreferencesAsync is needed.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// Same transitive package: the platform slot the in-memory backend goes in.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/service/beacon_child_command_store.dart';

/// Secure-storage contents that record every access. Every key holds a
/// value that cannot be decrypted, so any read of it throws a non-Exception
/// object, the way flutter_secure_storage_web lets a WebCrypto
/// DOMException escape.
final class _RecordingSecureBackend extends MapBase<String, String> {
  _RecordingSecureBackend(Map<String, String> raw) : raw = Map.of(raw);

  final Map<String, String> raw;
  final accessed = <String>[];

  @override
  String? operator [](Object? key) {
    accessed.add('read $key');
    // A JS DOMException is not a Dart Exception/Error; neither is a String.
    // ignore: only_throw_errors
    throw 'OperationError: stand-in for a WebCrypto DOMException';
  }

  @override
  void operator []=(String key, String value) {
    accessed.add('write $key');
    raw[key] = value;
  }

  @override
  void clear() {
    accessed.add('clear');
    raw.clear();
  }

  @override
  Iterable<String> get keys => raw.keys;

  @override
  String? remove(Object? key) {
    accessed.add('delete $key');
    return raw.remove(key);
  }
}

const _corrupted = 'q1w2e3r4.ZmFrZS1jaXBoZXJ0ZXh0';

/// What ordinary local storage holds under [key], whichever
/// shared_preferences API the store uses.
Future<String?> _localStorageValue(String key) async {
  final legacy = await SharedPreferences.getInstance();
  await legacy.reload();
  return legacy.getString(key) ?? await SharedPreferencesAsync().getString(key);
}

void main() {
  late _RecordingSecureBackend secure;

  setUp(() {
    secure = _RecordingSecureBackend({
      'beacon_create_op': _corrupted,
      'beacon_child_cmd:B1': _corrupted,
      'beacon_child_cmd:B1:M2': _corrupted,
    });
    FlutterSecureStorage.setMockInitialValues(secure);
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  for (final (label, context, key) in [
    (
      'standalone Request',
      const BeaconCreationContextStandalone(),
      'beacon_create_op',
    ),
    (
      'child Request',
      const BeaconCreationContextChild(parentBeaconId: 'B1'),
      'beacon_child_cmd:B1',
    ),
    (
      'Request promoted from a message',
      const BeaconCreationContextPromotedChild(
        parentBeaconId: 'B1',
        sourceMessageId: 'M2',
      ),
      'beacon_child_cmd:B1:M2',
    ),
  ]) {
    group('$label command id', () {
      test('starts empty even though secure storage holds an undecryptable '
          'value under the same key (no migration)', () async {
        expect(await BeaconChildCommandStore().read(context), isNull);
      });

      test('is written to ordinary local storage under "$key" and read '
          'back from there', () async {
        final store = BeaconChildCommandStore();

        await store.write(context, 'cmd-1');

        expect(await store.read(context), 'cmd-1');
        expect(await _localStorageValue(key), 'cmd-1');
      });

      test('clear removes it from ordinary local storage', () async {
        final store = BeaconChildCommandStore();
        await store.write(context, 'cmd-1');

        await store.clear(context);

        expect(await store.read(context), isNull);
        expect(await _localStorageValue(key), isNull);
      });

      test('never reads, writes or deletes secure storage, and leaves the '
          'old secure-storage value as it was', () async {
        final store = BeaconChildCommandStore();

        await store.read(context);
        await store.write(context, 'cmd-1');
        await store.read(context);
        await store.clear(context);

        expect(secure.accessed, isEmpty);
        expect(secure.raw[key], _corrupted);
      });
    });
  }
}
