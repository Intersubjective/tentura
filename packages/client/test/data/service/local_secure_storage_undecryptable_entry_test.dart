// An undecryptable secure-storage entry (on web: WebCrypto rejects with a JS
// DOMException 'OperationError', which is not a Dart Exception) must not
// crash the caller, must be reported to Sentry once without the value or the
// account id, and must never be deleted or overwritten — seeds are kept.
//
// The Sentry event carries the key category in the tag [_categoryTag]
// (snake_case like the app's other tags: `boot_step`, `auth_method`).
//
// The backend is flutter_secure_storage's own in-memory test platform over a
// map that throws a non-Exception object when an undecryptable key is read,
// the way flutter_secure_storage_web lets the DOMException escape.
import 'dart:collection';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/data/database/database.dart' hide isNotNull, isNull;
import 'package:tentura/data/service/local_secure_storage.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// Sentry tag whose value is the key category: account | session_marker |
/// beacon_command | other.
const _categoryTag = 'storage_key_category';
const _categories = {'account', 'session_marker', 'beacon_command', 'other'};

/// Stands in for the JS DOMException WebCrypto throws; deliberately not a
/// Dart [Exception] or [Error].
final class _FakeDomOperationError {
  const _FakeDomOperationError();

  @override
  String toString() =>
      'OperationError: The operation failed for an operation-specific reason';
}

/// Raw secure-storage contents. Reading a key in [undecryptable] throws
/// [_FakeDomOperationError]; every write and delete is recorded.
final class _UndecryptableBackend extends MapBase<String, String> {
  _UndecryptableBackend(Map<String, String> raw, this.undecryptable)
    : raw = Map.of(raw);

  final Map<String, String> raw;
  final Set<String> undecryptable;
  final writes = <String>[];
  final deletes = <String>[];

  @override
  String? operator [](Object? key) {
    if (undecryptable.contains(key)) {
      // The point of the fake: a thrown object that is not a Dart Exception.
      // ignore: only_throw_errors
      throw const _FakeDomOperationError();
    }
    return raw[key];
  }

  @override
  void operator []=(String key, String value) {
    writes.add(key);
    raw[key] = value;
  }

  @override
  void clear() {
    deletes.addAll(raw.keys);
    raw.clear();
  }

  @override
  Iterable<String> get keys => raw.keys;

  @override
  String? remove(Object? key) {
    deletes.add('$key');
    return raw.remove(key);
  }
}

class _RecordingTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}

const _accountId = 'U7f3c9a1b2d4e';
const _accountKey = 'Auth:Id:$_accountId';
const _sessionMarkerKey = 'Auth:Session:$_accountId';
const _currentAccountKey = 'Auth:currentAccountId';
const _ciphertext =
    'q1w2e3r4t5y6u7i8o9p0aa==.ZmFrZS1jaXBoZXJ0ZXh0LXVuZGVyLWFub3RoZXIta2V5';

void main() {
  late _UndecryptableBackend backend;
  late List<SentryEvent> events;

  void installBackend(Map<String, String> raw, Set<String> undecryptable) {
    backend = _UndecryptableBackend(raw, undecryptable);
    FlutterSecureStorage.setMockInitialValues(backend);
  }

  setUp(() async {
    events = <SentryEvent>[];
    await Sentry.init((options) {
      options
        ..dsn = 'https://public@example.invalid/1'
        ..debug = false
        ..enableDeduplication = false
        ..sendClientReports = false
        ..transport = _RecordingTransport();
      options.integrations.toList().forEach(options.removeIntegration);
      options.beforeSend = (event, hint) {
        events.add(event);
        return null;
      };
    });
  });

  tearDown(() async {
    await Sentry.close();
  });

  void expectUntouched(String key) {
    expect(
      backend.deletes,
      isNot(contains(key)),
      reason: 'an undecryptable entry must never be deleted',
    );
    expect(
      backend.writes,
      isNot(contains(key)),
      reason: 'an undecryptable entry must never be overwritten',
    );
    expect(backend.raw[key], _ciphertext);
  }

  /// The category tag: [_categoryTag] holds it, and no other tag carries a
  /// category value.
  String? categoryOf(SentryEvent event) {
    final tags = event.tags ?? const <String, String>{};
    expect(
      tags.entries
          .where((t) => t.key != _categoryTag && _categories.contains(t.value))
          .map((t) => t.key),
      isEmpty,
      reason: 'the key category is carried by the "$_categoryTag" tag only',
    );
    return tags[_categoryTag];
  }

  /// Handled = not fatal and not marked unhandled. A missing mechanism is
  /// handled under the Sentry protocol (`handled` defaults to true), which is
  /// what `Sentry.captureException` sends and how the app's own report
  /// helpers capture; the global error handlers that produced the fatal
  /// events set `handled: false` and level fatal.
  void expectHandledAndPrivate(SentryEvent event) {
    expect(event.level, isNot(SentryLevel.fatal));
    expect(
      event.exceptions?.map((e) => e.mechanism?.handled ?? true) ?? const [],
      everyElement(isTrue),
      reason: 'the decrypt failure is reported as handled',
    );
    final payload = jsonEncode(event.toJson());
    expect(
      payload,
      isNot(contains(_accountId)),
      reason: 'the Sentry event must not carry the account id',
    );
    expect(
      payload,
      isNot(contains(_ciphertext)),
      reason: 'the Sentry event must not carry the stored value',
    );
  }

  group('LocalSecureStorage with an entry that cannot be decrypted', () {
    test('read returns null instead of throwing', () async {
      installBackend({'other_key': _ciphertext}, {'other_key'});

      final value = await LocalSecureStorage().read('other_key');

      expect(value, isNull);
    });

    test(
      'boot init completes when the init entry cannot be decrypted',
      () async {
        installBackend({'init': _ciphertext}, {'init'});

        await expectLater(LocalSecureStorage().init(), completes);
      },
    );

    test('a failed read neither deletes nor overwrites the entry', () async {
      installBackend({_accountKey: _ciphertext}, {_accountKey});
      final storage = LocalSecureStorage();

      await storage.read(_accountKey);
      await storage.read(_accountKey);

      expectUntouched(_accountKey);
    });

    for (final (key, category) in [
      (_accountKey, 'account'),
      (_sessionMarkerKey, 'session_marker'),
      ('beacon_create_op', 'beacon_command'),
      ('beacon_child_cmd:B1', 'beacon_command'),
      ('beacon_child_cmd:B1:M2', 'beacon_command'),
      ('init', 'other'),
      (_currentAccountKey, 'other'),
    ]) {
      test(
        'a failed read of "$key" sends one handled Sentry event '
        'tagged "$category" without the value or the account id',
        () async {
          installBackend({key: _ciphertext}, {key});

          await LocalSecureStorage().read(key);

          expect(
            events,
            hasLength(1),
            reason: 'exactly one Sentry event per failed read',
          );
          final event = events.single;
          expect(
            categoryOf(event),
            category,
            reason: 'the event is tagged with the key category',
          );
          expectHandledAndPrivate(event);
        },
      );
    }
  });

  group(
    'LocalSecureStorage.readAll with an entry that cannot be decrypted',
    () {
      const readableId = 'Ureadable01';
      const readableKey = 'Auth:Id:$readableId';

      test(
        'returns the readable entries and leaves out the undecryptable one',
        () {
          installBackend(
            {readableKey: 'seed-readable', _accountKey: _ciphertext},
            {_accountKey},
          );

          return expectLater(
            LocalSecureStorage().readAll(),
            completion(
              allOf(
                containsPair(readableKey, 'seed-readable'),
                isNot(contains(_accountKey)),
              ),
            ),
          );
        },
      );

      test('neither deletes nor overwrites the undecryptable entry', () async {
        installBackend(
          {readableKey: 'seed-readable', _accountKey: _ciphertext},
          {_accountKey},
        );
        final storage = LocalSecureStorage();

        // Callers iterate what readAll returns.
        Map.of(await storage.readAll());
        Map.of(await storage.readAll());

        expectUntouched(_accountKey);
        expect(backend.raw[readableKey], 'seed-readable');
      });

      test(
        'sends one handled Sentry event per undecryptable entry, tagged with '
        'its key category, without the values or the account id',
        () async {
          installBackend(
            {
              readableKey: 'seed-readable',
              _accountKey: _ciphertext,
              _sessionMarkerKey: _ciphertext,
              'beacon_create_op': _ciphertext,
            },
            {_accountKey, _sessionMarkerKey, 'beacon_create_op'},
          );

          await LocalSecureStorage().readAll();

          expect(
            events,
            hasLength(3),
            reason: 'one Sentry event for each entry that failed to decrypt',
          );
          expect(
            [for (final event in events) categoryOf(event)],
            unorderedEquals(['account', 'session_marker', 'beacon_command']),
          );
          events.forEach(expectHandledAndPrivate);
        },
      );
    },
  );

  group('Cold boot with an undecryptable value in secure storage', () {
    const readableId = 'Ureadable01';
    const readableKey = 'Auth:Id:$readableId';

    test(
      'boot init and the account restore both complete, and the account '
      'with a readable seed is listed again',
      () async {
        installBackend(
          {
            'init': _ciphertext,
            readableKey: 'seed-readable',
            _accountKey: _ciphertext,
          },
          {'init', _accountKey},
        );
        // The restore runs when the local database had to be recreated: it
        // starts empty, with no account rows.
        final database = Database(
          const Env(),
          Logger('undecryptable-boot-test'),
          NativeDatabase.memory(),
        );
        addTearDown(database.close);
        final repository = AuthLocalRepository(
          Logger('undecryptable-boot-test'),
          database,
          LocalSecureStorage(),
        );
        expect(await repository.getAccountsAll(), isEmpty);

        await expectLater(LocalSecureStorage().init(), completes);
        await expectLater(
          AuthLocalRepository.restoreSeedAccounts(database.executor),
          completes,
        );

        expect(
          (await repository.getAccountsAll()).map((a) => a.id),
          contains(readableId),
          reason: 'restore inserts the ids of the readable account keys',
        );
        expectUntouched(_accountKey);
        expectUntouched('init');
      },
    );
  });

  group('Accounts whose stored seed cannot be decrypted', () {
    late Database database;
    late AuthLocalRepository repository;

    setUp(() async {
      installBackend(
        {_accountKey: _ciphertext, _currentAccountKey: _accountId},
        {_accountKey},
      );
      database = Database(
        const Env(),
        Logger('undecryptable-seed-test'),
        NativeDatabase.memory(),
      );
      addTearDown(database.close);
      await database.managers.accounts.create((o) => o(id: _accountId));
      repository = AuthLocalRepository(
        Logger('undecryptable-seed-test'),
        database,
        LocalSecureStorage(),
      );
    });

    test(
      'getSeedByAccountId answers with a localizable auth error instead of '
      'the raw decrypt failure, and the account stays in the account list',
      () async {
        await expectLater(
          repository.getSeedByAccountId(_accountId),
          throwsA(isA<AuthException>()),
          reason:
              'no seed can be returned; the caller gets the domain auth '
              'error it already handles (shown as a message, not a crash), '
              'never the raw storage error',
        );
        expect(
          (await repository.getAccountsAll()).map((a) => a.id),
          contains(_accountId),
        );
        expectUntouched(_accountKey);
      },
    );

    test(
      'storeLinkedSeedIfAbsent keeps the undecryptable seed instead of '
      'writing the new one over it',
      () async {
        Object? thrown;
        try {
          await repository.storeLinkedSeedIfAbsent(_accountId, 'new-seed');
        } on Object catch (error) {
          thrown = error;
        }

        expect(
          thrown,
          anyOf(isNull, isA<AuthException>()),
          reason:
              'it completes, or refuses with the domain auth error; the raw '
              'storage error must not reach the caller',
        );
        expectUntouched(_accountKey);
        expect(
          backend.writes,
          isEmpty,
          reason: 'linking must not write the seed while one is stored',
        );
      },
    );
  });
}
