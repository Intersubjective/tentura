@Tags(['pg', 'multi-connection', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts.dart' show kContextJwtKey;
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart' show Env;

import '../../../support/disposable_pg_target.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Uimportown001';
const _other = 'Uimportoth001';
const _newestKeyVersion = 7;
const _newestKey = 'contact-import-new-key';
const _normalizedEmail = 'anna@example.com';
const _phone = '+31 6 12345678';
const _batch = 'phantomCreateBatch';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_BATCH_IMPORT_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_batch_import',
  );
  final skip = await pgSkipReason(target);

  group('Importing people not on Tentura yet', () {
    late _ImportDatabase db;
    late _ImportApi api;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      db = _ImportDatabase(session.writer);
      final settings = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: settings.pgHost,
        pgPort: settings.pgPort,
        pgDatabase: settings.pgDatabase,
        pgUsername: settings.pgUsername,
        pgPassword: settings.pgPassword,
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        contactMatchHmacKeys: '$_newestKeyVersion:$_newestKey,2:older-key',
      );
      await configureSessionDatabaseTestGraph(env);
      api = _ImportApi(GraphqlController(env));
    });

    setUp(() => db.reset());

    group('45 contacts are committed in three groups of 20, 20 and 5', () {
      for (final keepContacts in [false, true]) {
        test(
          keepContacts
              ? 'every email has its own hash and normalized address'
              : 'every email has its own hash and a null address',
          () async {
            await db.recordInsertTransactions();
            final contacts = _numberedContacts(45);
            final names = contacts.map((row) => row.name).toList();
            final input = [
              for (final row in contacts)
                _contact(row.name, email: '  ${row.email!.toUpperCase()} '),
            ];

            _expectImported(
              await api.importContacts(input, keepContacts: keepContacts),
            );

            final people = await db.people();
            expect(people.map((row) => row['display_name']), names);
            expect(people.map((row) => row['owner_id']), everyElement(_owner));
            expect(people.map((row) => row['merged_at']), everyElement(isNull));
            expect(await db.committedNamesByTransaction(), [
              names.sublist(0, 20),
              names.sublist(20, 40),
              names.sublist(40),
            ]);
            for (final (index, person) in people.indexed) {
              final id = person['id']! as String;
              expect(await db.contactPoints(id), [
                _expectedEmailPoint(contacts[index].email!, keep: keepContacts),
              ], reason: 'Saved email for ${names[index]}');
            }
          },
        );
      }
    });

    test(
      'repeat imports add people to the same private Imported tag',
      () async {
        expect(await db.importedTags(_owner), isEmpty);
        // The importer's tag is independent of another person's same-named tag.
        await db.seedOtherImportedTag();

        _expectImported(
          await api.importContacts([
            _contact('Anna'),
            _contact('Boris'),
            _contact('Clara'),
          ]),
        );

        final tags = await db.importedTags(_owner);
        expect(tags, hasLength(1));
        final tag = tags.single;
        expect(await db.tagMemberNames(tag), ['Anna', 'Boris', 'Clara']);

        _expectImported(
          await api.importContacts([
            _contact('Diana'),
            _contact('Elena'),
          ]),
        );

        expect(await db.importedTags(_owner), [tag]);
        expect(await db.tagMemberNames(tag), [
          'Anna',
          'Boris',
          'Clara',
          'Diana',
          'Elena',
        ]);
        expect(
          await db.tagMemberNames((await db.importedTags(_other)).single),
          isEmpty,
        );
      },
    );

    test('imported people start without pins or invitations', () async {
      _expectImported(await api.importContacts(_numberedContacts(3)));

      expect(await db.people(), hasLength(3));
      final attachments = await db.connection.execute('''
SELECT 'pin', p.id
FROM public.phantom AS p
JOIN public.constellation_anchor AS a
  ON a.phantom_id = p.id OR a.target_id = p.id
UNION ALL
SELECT 'invite', p.id
FROM public.phantom AS p
JOIN public.invitation AS i ON i.phantom_id = p.id
''');
      expect(attachments, isEmpty);
    });

    test('names are trimmed before being cut to 32 characters', () async {
      const name = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn';

      _expectImported(
        await api.importContacts([
          _contact('  Anna Karenina  '),
          _contact('  $name  '),
        ]),
      );

      expect(
        (await db.people()).map((row) => row['display_name']),
        unorderedEquals(['Anna Karenina', name.substring(0, 32)]),
      );
    });

    test(
      'a short trimmed name is reported and uses no available place',
      () async {
        await db.seedActivePeople(198);
        final body = await api.importContacts(
          [
            _contact('Ana'),
            _contact(' Al '),
            _contact('Boris'),
          ],
          selection: 'refused { message }',
        );

        final result = _expectImported(body);
        expect(result['refused'], [
          containsPair(
            'message',
            allOf(
              matches(RegExp(r'\S')),
              isNot(matches(RegExp('phantom', caseSensitive: false))),
            ),
          ),
        ]);
        final people = await db.people();
        expect(people.where((row) => row['merged_at'] == null), hasLength(200));
        expect(
          people
              .map((row) => row['display_name'])
              .where((name) => name != 'Existing'),
          ['Ana', 'Boris'],
        );
      },
    );

    test(
      'the first contacts fill the remaining places and a full map gains none',
      () async {
        await db.seedActivePeople(195);
        final contacts = _numberedContacts(10);

        _expectImported(await api.importContacts(contacts));

        final after = await db.people();
        expect(after.where((row) => row['merged_at'] == null), hasLength(200));
        expect(
          after
              .map((row) => row['display_name'])
              .where((name) => name != 'Existing'),
          contacts.take(5).map((row) => row.name),
        );
        expect(after.map((row) => row['owner_id']), everyElement(_owner));

        final fullReply = await api.importContacts(
          _numberedContacts(3, startAt: 11),
        );
        if (fullReply['errors'] == null) {
          _expectImported(fullReply);
        } else {
          expect(fullReply['errors'], [
            anyOf(
              containsPair('message', 'phantom_cap_reached'),
              containsPair(
                'extensions',
                anyOf(
                  containsPair('code', 'phantom_cap_reached'),
                  containsPair('reason', 'phantom_cap_reached'),
                ),
              ),
            ),
          ], reason: jsonEncode(fullReply));
        }
        expect(await db.people(), after);
      },
    );

    for (final keepContacts in [false, true]) {
      test(
        keepContacts
            ? 'keeping details retains normalized email and unhashed phone'
            : 'discarding details leaves only the newest-version email hash',
        () async {
          _expectImported(
            await api.importContacts(
              [
                _contact('Anna', email: '  Anna@Example.COM ', phone: _phone),
              ],
              keepContacts: keepContacts,
            ),
          );

          final id = (await db.people()).single['id']! as String;
          expect(await db.contactPoints(id), [
            _expectedEmailPoint(_normalizedEmail, keep: keepContacts),
            if (keepContacts)
              {
                'kind': 'phone',
                'value': _phone,
                'hash': null,
                'hmac_key_version': null,
              },
          ]);
        },
      );
    }

    test('a first import initializes the owner’s first-seen state', () async {
      expect(await db.initializedViewers(), isEmpty);

      _expectImported(await api.importContacts(_numberedContacts(1)));

      expect(await db.people(), hasLength(1));
      expect(await db.initializedViewers(), [_owner]);
    });

    test(
      'deleting an imported person removes all of their saved contact points',
      () async {
        _expectImported(
          await api.importContacts(
            [
              _contact('Anna', email: _normalizedEmail, phone: _phone),
              _contact('Boris', email: 'boris@example.com'),
            ],
            keepContacts: true,
          ),
        );
        final [anna, boris] = (await db.people())
            .map((row) => row['id']! as String)
            .toList();
        expect(
          (await db.contactPoints(anna)).map((point) => point['kind']),
          ['email', 'phone'],
        );
        final untouched = await db.contactPoints(boris);
        expect(untouched, hasLength(1));

        final body = await api.delete(anna);
        expect(body['errors'], isNull, reason: jsonEncode(body));
        expect(body['data'], containsPair('phantomDelete', true));

        expect((await db.people()).map((row) => row['id']), [boris]);
        expect(await db.contactPoints(anna), isEmpty);
        expect(await db.contactPoints(boris), untouched);
        final cascade = await db.connection.execute('''
SELECT EXISTS (
  SELECT 1
  FROM pg_catalog.pg_constraint
  WHERE conrelid = 'public.phantom_contact_point'::regclass
    AND confrelid = 'public.phantom'::regclass
    AND contype = 'f' AND confdeltype = 'c' AND convalidated
)
''');
        expect(cascade.single.single, isTrue);
      },
    );

    test('saved contact details stay outside the Hasura API', () async {
      final storage = await db.connection.execute(
        "SELECT to_regclass('public.phantom_contact_point') IS NOT NULL",
      );
      expect(
        storage.single.single,
        isTrue,
        reason: 'The migrated database must have private contact storage.',
      );
      final document =
          jsonDecode(
                File('../../hasura/metadata.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      final metadata = document['metadata']! as Map<String, Object?>;
      expect(metadata['sources'], isNotEmpty);
      expect(jsonEncode(metadata), isNot(contains('phantom_contact_point')));
    });

    test('stored email hashes have an index for matching lookups', () async {
      final indexes = await db.connection.execute('''
SELECT idx.indexrelid
FROM pg_catalog.pg_index AS idx
JOIN pg_catalog.pg_attribute AS attr
  ON attr.attrelid = idx.indrelid AND attr.attnum = idx.indkey[0]
WHERE idx.indrelid = to_regclass('public.phantom_contact_point')
  AND attr.attname = 'match_hmac'
  AND idx.indisvalid AND idx.indisready
''');
      expect(
        indexes,
        isNotEmpty,
        reason: 'Contact storage must index match_hmac as a lookup key.',
      );
    });

    test(
      'a failure within the second chunk preserves only the first chunk',
      () async {
        await db.failOnTwentyFifthContact();
        final contacts = _numberedContacts(45);

        final reply = await api.importContacts(contacts);

        expect(
          await db.failedInsertAttempted(),
          isTrue,
          reason: jsonEncode(reply),
        );
        final people = await db.people();
        final savedNames = contacts.take(20).map((row) => row.name).toList();
        expect(people.map((row) => row['display_name']), savedNames);
        expect(people.map((row) => row['owner_id']), everyElement(_owner));
        expect(
          await db.tagMemberNames((await db.importedTags(_owner)).single),
          savedNames,
        );
        for (final (index, person) in people.indexed) {
          final id = person['id']! as String;
          expect(await db.contactPoints(id), [
            _expectedEmailPoint(contacts[index].email!),
          ], reason: 'Saved contact details for ${savedNames[index]}');
        }
      },
    );
  }, skip: skip);
}

typedef _Contact = ({String name, String? email, String? phone});

_Contact _contact(String name, {String? email, String? phone}) =>
    (name: name, email: email, phone: phone);

Map<String, Object?> _expectedEmailPoint(String email, {bool keep = false}) => {
  'kind': 'email',
  'value': keep ? email : null,
  'hash': Hmac(
    sha256,
    utf8.encode(_newestKey),
  ).convert(utf8.encode(email)).toString(),
  'hmac_key_version': _newestKeyVersion,
};

List<_Contact> _numberedContacts(int count, {int startAt = 1}) => [
  for (var i = startAt; i < startAt + count; i++)
    _contact(
      'Import contact ${i.toString().padLeft(2, '0')}',
      email: 'contact$i@example.com',
    ),
];

Map<String, Object?> _expectImported(Map<String, Object?> body) {
  expect(body['errors'], isNull, reason: jsonEncode(body));
  final data = body['data'];
  expect(data, containsPair(_batch, isA<Map<String, Object?>>()));
  return (data! as Map<String, Object?>)[_batch]! as Map<String, Object?>;
}

final class _ImportApi {
  const _ImportApi(this._controller);

  final GraphqlController _controller;

  Future<Map<String, Object?>> importContacts(
    List<_Contact> contacts, {
    bool keepContacts = false,
    String selection = '__typename',
  }) {
    final rows = [
      for (final contact in contacts)
        [
          'name: ${jsonEncode(contact.name)}',
          if (contact.email case final email?) 'email: ${jsonEncode(email)}',
          if (contact.phone case final phone?) 'phone: ${jsonEncode(phone)}',
        ].join(', '),
    ].map((row) => '{$row}').join(', ');
    return _post('''
mutation ImportContacts {
  $_batch(rows: [$rows], keepContacts: $keepContacts) { $selection }
}
''');
  }

  Future<Map<String, Object?>> delete(String id) => _post(
    'mutation RemoveContact { phantomDelete(id: ${jsonEncode(id)}) }',
  );

  Future<Map<String, Object?>> _post(String query) async {
    final response = await _controller.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        context: const {kContextJwtKey: JwtEntity(sub: _owner)},
        body: jsonEncode({'query': query}),
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, Object?>;
  }
}

final class _ImportDatabase {
  const _ImportDatabase(this.connection);

  final Connection connection;

  Future<void> reset() async {
    await connection.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final id in [_owner, _other]) {
      await connection.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': 'pk-$id'},
      );
    }
  }

  Future<List<Map<String, Object?>>> people() async {
    final rows = await connection.execute('''
SELECT id, owner_id, display_name, merged_at
FROM public.phantom
ORDER BY display_name COLLATE "C", id
''');
    return rows.map((row) => row.toColumnMap()).toList();
  }

  Future<void> seedActivePeople(int count) async {
    await connection.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
SELECT 'PH' || lpad(to_hex(n), 12, '0'), @owner, 'Existing'
FROM generate_series(1, @count::int) AS n
'''),
      parameters: {'owner': _owner, 'count': count},
    );
  }

  Future<void> seedOtherImportedTag() async {
    await connection.executeWithOwnerScopes(
      [_other],
      Sql.named('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES ('PTimportother', @owner, 'Imported', 'I', 0, 0)
'''),
      parameters: {'owner': _other},
    );
  }

  Future<Iterable<String>> importedTags(String owner) async {
    final rows = await connection.execute(
      Sql.named('''
SELECT id FROM public.person_tag WHERE owner_id = @owner AND name = 'Imported'
'''),
      parameters: {'owner': owner},
    );
    return rows.map((row) => row.single! as String);
  }

  Future<Iterable<String>> tagMemberNames(String tagId) async {
    final rows = await connection.execute(
      Sql.named('''
SELECT p.display_name
FROM public.phantom_tag_member AS m
JOIN public.phantom AS p ON p.id = m.phantom_id
WHERE m.tag_id = @tag
ORDER BY p.display_name COLLATE "C"
'''),
      parameters: {'tag': tagId},
    );
    return rows.map((row) => row.single! as String);
  }

  Future<Iterable<String>> initializedViewers() async {
    final rows = await connection.execute(
      'SELECT viewer_id FROM public.person_field_first_seen_init',
    );
    return rows.map((row) => row.single! as String);
  }

  Future<List<Map<String, Object?>>> contactPoints(String id) async {
    final rows = await connection.execute(
      Sql.named('''
SELECT kind, value, encode(match_hmac, 'hex') AS hash, hmac_key_version
FROM public.phantom_contact_point
WHERE phantom_id = @id
ORDER BY kind
'''),
      parameters: {'id': id},
    );
    return rows.map((row) => row.toColumnMap()).toList();
  }

  Future<void> _createProbeSchema() async {
    await connection.execute('CREATE SCHEMA contact_import_probe');
    addTearDown(
      () => connection.execute('DROP SCHEMA contact_import_probe CASCADE'),
    );
  }

  Future<void> recordInsertTransactions() async {
    await _createProbeSchema();
    await connection.execute('''
CREATE TABLE contact_import_probe.insertions (
  ordinal bigint GENERATED ALWAYS AS IDENTITY,
  transaction_id text NOT NULL,
  display_name text NOT NULL
)
''');
    // The top-level transaction ID is shared by all savepoints of one commit.
    await connection.execute(r'''
CREATE FUNCTION contact_import_probe.record_insertion() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO contact_import_probe.insertions (transaction_id, display_name)
    VALUES (pg_current_xact_id()::text, NEW.display_name);
  RETURN NEW;
END;
$$
''');
    await connection.execute('''
CREATE TRIGGER record_contact_import
AFTER INSERT ON public.phantom
FOR EACH ROW EXECUTE FUNCTION contact_import_probe.record_insertion()
''');
  }

  Future<List<Object?>> committedNamesByTransaction() async {
    final rows = await connection.execute('''
SELECT array_agg(display_name ORDER BY display_name COLLATE "C")
FROM contact_import_probe.insertions
GROUP BY transaction_id
ORDER BY min(ordinal)
''');
    return rows.map((row) => row.single).toList();
  }

  Future<void> failOnTwentyFifthContact() async {
    await _createProbeSchema();
    await connection.execute(
      'CREATE SEQUENCE contact_import_probe.failed_insert',
    );
    await connection.execute(r'''
CREATE FUNCTION contact_import_probe.refuse_insertion() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.display_name = 'Import contact 25' THEN
    -- Sequence state survives the rollback so the test can confirm the fault ran.
    PERFORM nextval('contact_import_probe.failed_insert');
    RAISE EXCEPTION 'Contact import test fault';
  END IF;
  RETURN NEW;
END;
$$
''');
    await connection.execute('''
CREATE TRIGGER refuse_contact_import
BEFORE INSERT ON public.phantom
FOR EACH ROW EXECUTE FUNCTION contact_import_probe.refuse_insertion()
''');
  }

  Future<bool> failedInsertAttempted() async {
    final rows = await connection.execute(
      'SELECT is_called FROM contact_import_probe.failed_insert',
    );
    return rows.single.single! as bool;
  }
}
