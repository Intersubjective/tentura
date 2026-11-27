@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/contact_match_storage.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';
import 'package:tentura_server/domain/util/contact_match_key_ring.dart';
import 'package:tentura_server/env.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';
import '../support/session_database_di_harness.dart';

const _keyConfig = '1:old,2:new';
const _aliceEmail = 'alice@example.com';
const _phoneNumber = '+12025550100';
const _firstOwner = 'Ukeyrotation01';
const _secondOwner = 'Ukeyrotation02';
const _firstEmail = 'first@example.com';
const _secondEmail = 'second@example.com';
const _phantomId = 'PH0123456789ab';

Future<void> main() async {
  final authTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VERIFIED_EMAIL_HASH_TEST_DB',
    defaultNamePrefix: 'tentura_test_verified_email_hash',
    useDevBindings: true,
  );
  final rotationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VERIFIED_EMAIL_ROTATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_verified_email_rotation',
    useDevBindings: true,
  );
  final backfillTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_VERIFIED_EMAIL_BACKFILL_TEST_DB',
    defaultNamePrefix: 'tentura_test_verified_email_backfill',
  );

  group('Verified contact hashes from credential authentication', () {
    late Connection writer;
    late ContactMatchKeyRing ring;
    late CredentialAuthCase auth;

    setUpAll(() async {
      writer = await _openDatabaseWithSessionGraph(authTarget);
      ring = getIt<Env>().contactMatchKeyRing;
      auth = getIt<CredentialAuthCase>();
    });

    test('migrations add nullable digest and key version columns', () async {
      final columns = await writer.execute('''
SELECT column_name::text, data_type::text, is_nullable::text
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'account_verified_contact'
  AND column_name IN ('match_hmac', 'hmac_key_version')
''');
      expect(
        columns.map((row) => row.toList()),
        unorderedEquals([
          ['match_hmac', 'bytea', 'YES'],
          ['hmac_key_version', 'smallint', 'YES'],
        ]),
      );
    });

    test('migrations index verified contact digests for lookup', () async {
      final index = await writer.execute('''
SELECT EXISTS (
  SELECT 1
  FROM pg_index AS i
  JOIN pg_attribute AS a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
  WHERE i.indrelid = 'public.account_verified_contact'::regclass
    AND a.attname = 'match_hmac' AND i.indisvalid AND i.indisready
)
''');
      expect(index.single.single, isTrue);
    });

    test(
      'signup stores a matchable email digest and leaves the phone unhashed',
      () async {
        final signup = await auth.resolveOrCreate(
          type: CredentialType.emailOtp,
          identifier: _aliceEmail,
          displayName: 'Alice',
          assertedContacts: [
            AssertedContact.email(rawEmail: _aliceEmail, authoritative: true)!,
            const _AuthoritativePhone(),
          ],
        );
        addTearDown(() => _removeContacts(writer, signup.accountId));
        expect(signup.isNewAccount, isTrue);

        await _expectStoredMatch(writer, ring, signup.accountId);
      },
    );

    test(
      'returning login stores a matchable normalized email digest and leaves the phone unhashed',
      () async {
        final signup = await auth.resolveOrCreate(
          type: CredentialType.oidcGoogle,
          identifier: 'google-sub-returning-alice',
          displayName: 'Alice',
        );
        addTearDown(() => _removeContacts(writer, signup.accountId));
        expect(signup.isNewAccount, isTrue);

        final login = await auth.resolveOrCreate(
          type: CredentialType.oidcGoogle,
          identifier: 'google-sub-returning-alice',
          displayName: 'Alice',
          assertedContacts: [
            AssertedContact.email(
              rawEmail: ' Alice@Example.COM ',
              authoritative: true,
            )!,
            const _AuthoritativePhone(),
          ],
        );
        expect(login, (accountId: signup.accountId, isNewAccount: false));

        await _expectStoredMatch(writer, ring, login.accountId);
      },
    );
  }, skip: await pgSkipReason(authTarget));

  group('One-shot verified email hash backfill', () {
    late Connection writer;

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: backfillTarget);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      await _addContactHashColumns(writer);
      await _seedBackfillContacts(writer);
    });

    test(
      'one-shot backfill hashes all legacy emails once and preserves already hashed contacts and phones',
      () async {
        final before = await _storedContacts(writer);

        await _runOneShotMigrationCommand(backfillTarget.databaseEnv);
        final firstRun = await _storedContacts(writer);
        await _runOneShotMigrationCommand(backfillTarget.databaseEnv);
        final secondRun = await _storedContacts(writer);

        expect(firstRun['existing'], before['existing']);
        expect(firstRun['phone'], before['phone']);
        expect(firstRun['phone']?.digest, (null, null));
        expect(secondRun, firstRun);
        expect(
          {
            'first legacy email': firstRun['first']?.digest,
            'second legacy email': firstRun['second']?.digest,
          },
          {
            'first legacy email': (2, _digest('new', _firstEmail)),
            'second legacy email': (2, _digest('new', _secondEmail)),
          },
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: await pgSkipReason(backfillTarget));

  group('Verified email key rotation in the task worker', () {
    late Connection writer;

    setUpAll(() async {
      writer = await _openDatabaseWithSessionGraph(rotationTarget);
      // Model a database that has already stored digests under both keys.
      // The migration tests use a separate database with the real schema alone.
      await _addContactHashColumns(writer);
      await _seedRotationContacts(writer);
    });

    test(
      'rekeys old email digests, preserves other contacts and allows an unused key to retire',
      () async {
        final worker = await getIt.getAsync<TaskWorkerCase>();
        final database = getIt<TenturaDb>();
        addTearDown(database.close);
        final databaseName = await database.withConnectionScope(
          () => database
              .customSelect('SELECT current_database()::text AS name')
              .getSingle(),
        );
        expect(
          databaseName.read<String>('name'),
          rotationTarget.databaseName,
          reason: 'The task worker graph must connect to the seeded database.',
        );

        final oldKey = ContactMatchKeyRing.parse('1:old');
        final newestKey = ContactMatchKeyRing.parse('2:new');
        final ring = worker.env.contactMatchKeyRing;
        await checkStoredContactMatchKeys(writer, ring);
        expect(await _lookup(writer, oldKey, _firstEmail), {_firstOwner});
        expect(await _lookup(writer, oldKey, _secondEmail), {_secondOwner});
        expect(await _lookup(writer, newestKey, _firstEmail), isEmpty);
        expect(await _lookup(writer, newestKey, _secondEmail), isEmpty);
        final before = await _storedContacts(writer);
        final phantomBefore = await _phantomContact(writer);

        await worker.tick().timeout(const Duration(seconds: 15));

        expect(await _phantomContact(writer), phantomBefore);
        final after = await _storedContacts(writer);
        expect(after['current'], before['current']);
        expect(after['phone'], before['phone']);
        expect(
          {
            'first digest': after['first']?.digest,
            'second digest': after['second']?.digest,
            'first lookup with newest key': await _lookup(
              writer,
              newestKey,
              _firstEmail,
            ),
            'second lookup with newest key': await _lookup(
              writer,
              newestKey,
              _secondEmail,
            ),
          },
          {
            'first digest': (2, _digest('new', _firstEmail)),
            'second digest': (2, _digest('new', _secondEmail)),
            'first lookup with newest key': {_firstOwner},
            'second lookup with newest key': {_secondOwner},
          },
        );

        await expectLater(
          checkStoredContactMatchKeys(writer, newestKey),
          throwsStateError,
        );
        await writer.executeWithOwnerScopes(
          [_firstOwner],
          '''
DELETE FROM public.phantom_contact_point WHERE phantom_id = '$_phantomId'
''',
        );
        await checkStoredContactMatchKeys(writer, newestKey);
      },
    );
  }, skip: await pgSkipReason(rotationTarget));
}

// Models a phone already verified by the credential provider. The auth DTO
// currently has a convenience factory only for email.
class _AuthoritativePhone implements AssertedContact {
  const _AuthoritativePhone();

  @override
  ContactKind get kind => ContactKind.phone;

  @override
  String get value => _phoneNumber;

  @override
  bool get authoritative => true;
}

Future<Connection> _openDatabaseWithSessionGraph(
  DisposablePgTarget target,
) async {
  final session = await setUpDisposablePgWriter(target: target);
  addTearDown(() => tearDownDisposablePgWriter(session: session));
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  addTearDown(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
  });
  addTearDown(() async {
    getIt.skipDoubleRegistration = false;
    await getIt.reset();
  });
  final base = target.databaseEnv;
  await configureSessionDatabaseTestGraph(
    Env(
      environment: base.environment,
      pgHost: base.pgHost,
      pgPort: base.pgPort,
      pgDatabase: base.pgDatabase,
      pgUsername: base.pgUsername,
      pgPassword: base.pgPassword,
      serverUri: base.serverUri,
      publicOrigin: base.publicOrigin,
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      workersCount: 1,
      printEnv: false,
      isDebugModeOn: false,
      isNeedInvite: false,
      contactMatchHmacKeys: _keyConfig,
      sentryDsn: '',
    ),
  );
  return session.writer;
}

Future<void> _removeContacts(Connection writer, String accountId) async {
  await writer.execute(
    Sql.named(
      'DELETE FROM public.account_verified_contact WHERE account_id = @id',
    ),
    parameters: {'id': accountId},
  );
}

Future<void> _expectStoredMatch(
  Connection writer,
  ContactMatchKeyRing ring,
  String accountId,
) async {
  // Read the persisted row even before the digest columns have been migrated.
  final rows = await writer.execute(
    Sql.named('''
SELECT value,
       kind,
       (to_jsonb(contact)->>'hmac_key_version')::smallint,
       encode((to_jsonb(contact)->>'match_hmac')::bytea, 'hex')
FROM public.account_verified_contact AS contact
WHERE account_id = @id
ORDER BY kind, value
'''),
    parameters: {'id': accountId},
  );
  expect(
    {
      'stored contacts': rows.map((row) => row.toList()).toList(),
      'matching accounts': await _lookup(writer, ring, _aliceEmail),
    },
    {
      'stored contacts': [
        [_aliceEmail, 'email', 2, _digest('new', _aliceEmail)],
        [_phoneNumber, 'phone', null, null],
      ],
      'matching accounts': {accountId},
    },
  );
}

String _digest(String secret, String email) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(email)).toString();

Future<Set<String>> _lookup(
  Connection writer,
  ContactMatchKeyRing ring,
  String email,
) => findMatchingVerifiedAccounts(
  writer,
  ring,
  kind: ContactKind.email,
  value: email,
);

Future<void> _addContactHashColumns(Connection writer) async {
  // These fixtures start with a database where the storage migration has run.
  // The separate migration tests check the actual schema without fixture DDL.
  await writer.execute('''
ALTER TABLE public.account_verified_contact
  ADD COLUMN IF NOT EXISTS match_hmac bytea,
  ADD COLUMN IF NOT EXISTS hmac_key_version smallint
''');
}

Future<void> _seedBackfillContacts(Connection writer) async {
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_firstOwner', 'First', '${pgTestPublicKey('backfill', 1)}'),
       ('$_secondOwner', 'Second', '${pgTestPublicKey('backfill', 2)}')
''');
  await writer.execute('''
INSERT INTO public.account_verified_contact
  (id, account_id, kind, value, last_source, match_hmac, hmac_key_version)
VALUES
  ('first', '$_firstOwner', 'email', ' First@Example.COM ', 'email_otp', NULL, NULL),
  ('second', '$_secondOwner', 'email', '$_secondEmail', 'email_otp', NULL, NULL),
  ('existing', '$_firstOwner', 'email', 'existing@example.com', 'email_otp',
   decode('${_digest('old', 'existing@example.com')}', 'hex'), 1),
  ('phone', '$_secondOwner', 'phone', '$_phoneNumber', 'email_otp', NULL, NULL)
''');
}

Future<void> _runOneShotMigrationCommand(Env database) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['bin/utils/run_migrations_once.dart'],
    includeParentEnvironment: false,
    environment: {
      'POSTGRES_HOST': database.pgHost,
      'POSTGRES_PORT': '${database.pgPort}',
      'POSTGRES_DBNAME': database.pgDatabase,
      'POSTGRES_USERNAME': database.pgUsername,
      'POSTGRES_PASSWORD': database.pgPassword,
      'CONTACT_MATCH_HMAC_KEYS': _keyConfig,
    },
  );
  final output = Future.wait([
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
  ]);
  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(seconds: 35));
  } finally {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
  expect(exitCode, 0, reason: (await output).join('\n'));
}

Future<void> _seedRotationContacts(Connection writer) async {
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_firstOwner', 'First', '${pgTestPublicKey('rotation', 1)}'),
       ('$_secondOwner', 'Second', '${pgTestPublicKey('rotation', 2)}')
''');
  await writer.execute('''
INSERT INTO public.account_verified_contact
  (id, account_id, kind, value, last_source, match_hmac, hmac_key_version)
VALUES
  ('first', '$_firstOwner', 'email', ' First@Example.COM ', 'email_otp',
   decode('${_digest('old', _firstEmail)}', 'hex'), 1),
  ('second', '$_secondOwner', 'email', '$_secondEmail', 'email_otp',
   decode('${_digest('old', _secondEmail)}', 'hex'), 1),
  ('current', '$_firstOwner', 'email', 'current@example.com', 'email_otp',
   decode('${_digest('new', 'current@example.com')}', 'hex'), 2),
  ('phone', '$_secondOwner', 'phone', '$_phoneNumber', 'email_otp', NULL, NULL)
''');
  await writer.executeWithOwnerScopes(
    [_firstOwner],
    '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES ('$_phantomId', '$_firstOwner', 'Private contact')
''',
  );
  await writer.executeWithOwnerScopes(
    [_firstOwner],
    '''
INSERT INTO public.phantom_contact_point
  (phantom_id, kind, value, match_hmac, hmac_key_version)
VALUES ('$_phantomId', 'email', NULL,
        decode('${_digest('old', 'private@example.com')}', 'hex'), 1)
''',
  );
}

typedef _StoredContact = ({
  (int?, String?) digest,
  String snapshot,
  String transactionId,
});

Future<Map<String, _StoredContact>> _storedContacts(Connection writer) async {
  final rows = await writer.execute('''
SELECT id, hmac_key_version, encode(match_hmac, 'hex'),
       to_jsonb(contact)::text, contact.xmin::text
FROM public.account_verified_contact AS contact
''');
  return {
    for (final row in rows)
      row[0]! as String: (
        digest: (row[1] as int?, row[2] as String?),
        snapshot: row[3]! as String,
        transactionId: row[4]! as String,
      ),
  };
}

Future<String> _phantomContact(Connection writer) async {
  final rows = await writer.execute('''
SELECT to_jsonb(point)::text
FROM public.phantom_contact_point AS point WHERE phantom_id = '$_phantomId'
''');
  return rows.single.single! as String;
}
