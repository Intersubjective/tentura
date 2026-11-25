@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

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
import 'package:tentura_server/utils/id.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'Uphantomown01';
const _other = 'Uphantomoth01';
const _phantom = 'PHfedcba987654';
const _unknown = 'PHfedcba987655';
const _shortName = ' ab ';
const _longName = 'abcdefghijklmnopqrstuvwxyzABCDEFG';
const _maxName = 'abcdefghijklmnopqrstuvwxyzABCDEF';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_MUTATIONS_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_mutations',
  );
  final skip = await pgSkipReason(target);

  group('V2 mutations for people not on Tentura yet', () {
    late _PhantomFixtures fixtures;
    late _PhantomApi api;

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
      fixtures = _PhantomFixtures(session.writer);

      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      await configureSessionDatabaseTestGraph(env);
      api = _PhantomApi(GraphqlController(env));
      await api.readMutationResultKinds();
    });

    setUp(() async {
      await fixtures.reset();
    });

    group('adding someone', () {
      test(
        'returns a 14-character id and stores the owner, trimmed name, and emoji',
        () async {
          final id = _createdId(await api.create('  Anna K.  ', emoji: '🌻'));

          expect(
            await fixtures.phantom(id),
            allOf(
              containsPair('owner_id', _owner),
              containsPair('display_name', 'Anna K.'),
              containsPair('emoji', '🌻'),
              containsPair('merged_at', null),
            ),
          );
        },
      );

      test(
        'omitting a Field position and emoji leaves the person unpinned and emoji unset',
        () async {
          final id = _createdId(await api.create('Anna K.'));

          expect(await fixtures.phantom(id), containsPair('emoji', null));
          expect(await fixtures.pins(id), isEmpty);
        },
      );

      test(
        'adding at a Field position pins that person at the supplied coordinates',
        () async {
          final id = _createdId(
            await api.create('Anna K.', withPosition: true),
          );

          expect(await fixtures.pins(id), [
            {
              'viewer_id': _owner,
              'target_kind': 'PHANTOM',
              'phantom_id': id,
              'x_units': 3.5,
              'y_units': -4.25,
              'coordinate_space_version': 1,
              'tombstone_at': null,
            },
          ]);
        },
      );

      for (final (length, invalidName) in [(2, _shortName), (33, _longName)]) {
        test(
          'a name of $length characters after trimming is rejected without a new person',
          () async {
            _expectNameError(await api.create(invalidName));
            expect(await fixtures.phantomCount(), 0);
          },
        );
      }

      test('names of exactly 3 and 32 characters are accepted', () async {
        for (final name in ['Ana', _maxName]) {
          final id = _createdId(await api.create(name));
          expect(
            await fixtures.phantom(id),
            containsPair('display_name', name),
          );
        }
      });

      test(
        'an emoji over eight characters is rejected without adding a person',
        () async {
          final body = await api.create('Anna K.', emoji: '☀☀☀☀☀☀☀☀☀');

          expect(body['errors'], isNotEmpty, reason: jsonEncode(body));
          expect(_dataField(body, 'phantomCreate'), isNull);
          expect(await fixtures.phantomCount(), 0);

          // The same request with a valid length is accepted.
          const validEmoji = '☀☀☀☀☀☀☀☀';
          final id = _createdId(await api.create('Anna K.', emoji: validEmoji));
          expect(await fixtures.phantom(id), containsPair('emoji', validEmoji));
        },
      );

      test(
        'the first add creates a pending first-seen marker for the owner',
        () async {
          expect(await fixtures.initMarkers(_owner), isEmpty);

          _createdId(await api.create('Anna K.'));

          final marker = (await fixtures.initMarkers(_owner)).single;
          expect(marker['backfill_pending'], isTrue);
          expect(await fixtures.initMarkers(_other), isEmpty);
        },
      );

      for (final pending in [true, false]) {
        final state = pending ? 'pending' : 'completed';
        test(
          'adding someone preserves an existing $state first-seen marker',
          () async {
            await fixtures.seedInitMarker(pending: pending);
            final before = (await fixtures.initMarkers(_owner)).single;

            _createdId(await api.create('Anna K.'));

            expect(await fixtures.initMarkers(_owner), [before]);
          },
        );
      }
    });

    group('active places available to each owner', () {
      test('an owner with 200 active people cannot add a 201st', () async {
        await fixtures.seedActive(_owner, 200);

        _expectCapError(await api.create('One too many'));

        expect(await fixtures.activeCount(_owner), 200);
      });

      test(
        'two simultaneous adds compete for the last available place',
        () async {
          await fixtures.seedActive(_owner, 199);

          final replies = await Future.wait([
            api.create('First contender'),
            api.create('Second contender'),
          ]).timeout(const Duration(seconds: 30));

          final accepted = replies.where((body) => body['errors'] == null);
          final rejected = replies.where((body) => body['errors'] != null);
          expect(accepted, hasLength(1), reason: jsonEncode(replies));
          expect(rejected, hasLength(1), reason: jsonEncode(replies));
          final id = _createdId(accepted.single);
          expect(await fixtures.phantom(id), containsPair('owner_id', _owner));
          _expectCapError(rejected.single);
          expect(await fixtures.activeCount(_owner), 200);
        },
      );

      test(
        'a person already linked to an account does not use an active place',
        () async {
          await fixtures.seedActive(_owner, 199);
          await fixtures.seedPhantom(merged: true);

          final id = _createdId(await api.create('One more person'));

          expect(await fixtures.phantom(id), containsPair('merged_at', null));
          expect(await fixtures.activeCount(_owner), 200);
          expect(
            (await fixtures.phantom(_phantom))?['merged_at'],
            isNotNull,
          );
        },
      );

      test(
        'another owner with 200 active people does not use my places',
        () async {
          await fixtures.seedActive(_other, 200);

          final id = _createdId(await api.create('My first person'));

          expect(await fixtures.phantom(id), containsPair('owner_id', _owner));
          expect(await fixtures.activeCount(_owner), 1);
          expect(await fixtures.activeCount(_other), 200);
        },
      );

      test('deleting someone frees a place for another person', () async {
        await fixtures.seedActive(_owner, 199);
        await fixtures.seedPhantom();
        expect(await fixtures.activeCount(_owner), 200);

        _expectSuccess(await api.delete(_phantom), 'phantomDelete');
        expect(await fixtures.activeCount(_owner), 199);

        final id = _createdId(await api.create('Replacement'));

        expect(await fixtures.phantom(id), containsPair('owner_id', _owner));
        expect(await fixtures.activeCount(_owner), 200);
      });
    });

    group('renaming someone', () {
      setUp(() async {
        await fixtures.seedPhantom();
      });

      test(
        'the owner can use a 14-character id to change name and emoji',
        () async {
          final before = (await fixtures.phantom(_phantom))!;

          _expectSuccess(
            await api.update(_phantom, 'Anna Karenina'),
            'phantomUpdate',
          );

          final after = (await fixtures.phantom(_phantom))!;
          expect(after['display_name'], 'Anna Karenina');
          expect(after['emoji'], '🎻');
          expect(after['revision'], greaterThan(before['revision']!));
        },
      );

      for (final (length, invalidName) in [(2, _shortName), (33, _longName)]) {
        test(
          'a rename to $length characters after trimming leaves the person unchanged',
          () async {
            final before = await fixtures.phantom(_phantom);

            _expectNameError(await api.update(_phantom, invalidName));

            expect(await fixtures.phantom(_phantom), before);
          },
        );
      }

      test('a rename accepts names of exactly 3 and 32 characters', () async {
        for (final name in ['Ana', _maxName]) {
          _expectSuccess(await api.update(_phantom, name), 'phantomUpdate');
          expect(
            await fixtures.phantom(_phantom),
            containsPair('display_name', name),
          );
        }
      });

      test(
        'renaming someone on another owner’s map returns not-found',
        () async {
          final before = (await fixtures.phantom(_phantom))!;

          _expectNotFound(
            await api.update(_phantom, 'Another name', as: _other),
          );

          expect(await fixtures.phantom(_phantom), before);
        },
      );

      test('renaming an unknown id returns not-found', () async {
        _expectNotFound(await api.update(_unknown, 'Another name'));
      });
    });

    group('deleting someone', () {
      setUp(() async {
        await fixtures.seedPhantom();
      });

      test(
        'deleting a 14-character id removes the person and their Field pin',
        () async {
          await fixtures.seedPin();
          expect(await fixtures.pins(_phantom), hasLength(1));

          _expectSuccess(await api.delete(_phantom), 'phantomDelete');

          expect(await fixtures.phantom(_phantom), isNull);
          expect(await fixtures.pins(_phantom), isEmpty);
          _expectNotFound(await api.delete(_phantom));
          _expectNotFound(await api.update(_phantom, 'Another name'));
        },
      );

      test(
        'deleting a person removes their Field pin, tag membership, and invite',
        () async {
          final id = _createdId(
            await api.create('Anna K.', withPosition: true),
          );
          expect(await fixtures.pins(id), hasLength(1));
          await fixtures.requireDeleteRelations();
          final membership = await fixtures.seedTagMembership(id);
          final invitation = await fixtures.seedInvitation(id);
          expect((await fixtures.tagMemberships(membership)).single.single, id);
          expect((await fixtures.invitations(invitation)).single.single, id);

          _expectSuccess(await api.delete(id), 'phantomDelete');

          expect(await fixtures.phantom(id), isNull);
          expect(await fixtures.pins(id), isEmpty);
          expect(await fixtures.tagMemberships(membership), isEmpty);
          expect(await fixtures.invitations(invitation), isEmpty);
        },
      );

      test(
        'deleting someone on another owner’s map returns not-found',
        () async {
          final before = (await fixtures.phantom(_phantom))!;

          _expectNotFound(await api.delete(_phantom, as: _other));

          expect(await fixtures.phantom(_phantom), before);
        },
      );

      test('deleting an unknown id returns not-found', () async {
        _expectNotFound(await api.delete(_unknown));
      });
    });
  }, skip: skip);
}

Object? _dataField(Map<String, Object?> body, String mutation) =>
    (body['data'] as Map<String, dynamic>?)?[mutation];

void _expectSuccess(Map<String, Object?> body, String mutation) {
  expect(body['errors'], isNull, reason: jsonEncode(body));
  expect(_dataField(body, mutation), allOf(isNotNull, isNot(false)));
}

String _createdId(Map<String, Object?> body) {
  _expectSuccess(body, 'phantomCreate');
  final value = _dataField(body, 'phantomCreate');
  final id = value is Map<String, dynamic> ? value['id'] : value;
  expect(id, matches(RegExp(r'^PH[0-9a-f]{12}$')));
  return id! as String;
}

void _expectNameError(Map<String, Object?> body) {
  expect(body['errors'], [
    allOf(
      containsPair('extensions', containsPair('code', '1001')),
      containsPair('message', 'Contact name must be 3–32 characters long'),
    ),
  ], reason: jsonEncode(body));
}

void _expectNotFound(Map<String, Object?> body) {
  expect(body['errors'], [
    containsPair('extensions', containsPair('code', '1002')),
  ], reason: jsonEncode(body));
}

void _expectCapError(Map<String, Object?> body) {
  const reason = 'phantom_cap_reached';
  expect(body['errors'], [
    anyOf(
      containsPair('message', reason),
      containsPair(
        'extensions',
        anyOf(containsPair('code', reason), containsPair('reason', reason)),
      ),
    ),
  ], reason: jsonEncode(body));
}

final class _PhantomApi {
  _PhantomApi(this._controller);

  final GraphqlController _controller;
  late final Map<String, String> _resultKinds;

  Future<void> readMutationResultKinds() async {
    final body = await _post('''
{
  __type(name: "Mutation") {
    fields { name type { kind ofType { kind } } }
  }
}
''', const {});
    expect(body['errors'], isNull, reason: jsonEncode(body));
    final type = _dataField(body, '__type')! as Map<String, dynamic>;
    final fields = type['fields']! as List<dynamic>;
    _resultKinds = {
      for (final field in fields.cast<Map<String, dynamic>>())
        field['name']! as String: _kind(field['type'] as Map<String, dynamic>),
    };
  }

  static String _kind(Map<String, dynamic> type) =>
      (type['kind'] == 'NON_NULL'
              ? (type['ofType'] as Map<String, dynamic>)['kind']
              : type['kind'])
          as String;

  // The create contract includes an id. Accept the id directly or as the id
  // field of a record. Update and delete are verified by their persisted effects.
  String _selection(String mutation) => switch (_resultKinds[mutation]) {
    'OBJECT' when mutation == 'phantomCreate' => ' { id }',
    'OBJECT' => ' { __typename }',
    _ => '',
  };

  Future<Map<String, Object?>> create(
    String name, {
    String? emoji,
    bool withPosition = false,
  }) {
    final emojiVariable = emoji == null ? '' : r', $emoji: String!';
    final emojiArgument = emoji == null ? '' : r', emoji: $emoji';
    const position =
        ', position: {xUnits: 3.5, yUnits: -4.25, coordinateSpaceVersion: 1}';
    return _post(
      r'mutation AddPerson($name: String!'
      '$emojiVariable) { '
      r'phantomCreate(name: $name'
      '$emojiArgument${withPosition ? position : ''})'
      '${_selection('phantomCreate')} }',
      {'name': name, 'emoji': ?emoji},
    );
  }

  Future<Map<String, Object?>> update(
    String id,
    String name, {
    String as = _owner,
  }) => _post(
    r'mutation RenamePerson($id: String!, $name: String!, $emoji: String!) {'
    r' phantomUpdate(id: $id, name: $name, emoji: $emoji)'
    '${_selection('phantomUpdate')} }',
    {'id': id, 'name': name, 'emoji': '🎻'},
    as: as,
  );

  Future<Map<String, Object?>> delete(String id, {String as = _owner}) => _post(
    r'mutation RemovePerson($id: String!) { phantomDelete(id: $id)'
    '${_selection('phantomDelete')} }',
    {'id': id},
    as: as,
  );

  Future<Map<String, Object?>> _post(
    String query,
    Map<String, Object?> variables, {
    String as = _owner,
  }) async {
    final response = await _controller.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        context: {kContextJwtKey: JwtEntity(sub: as)},
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, Object?>;
  }
}

final class _PhantomFixtures {
  const _PhantomFixtures(this._writer);

  final Connection _writer;

  Future<void> reset() async {
    await _writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final id in [_owner, _other]) {
      await _writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': 'pk-$id'},
      );
    }
  }

  Future<void> seedActive(String owner, int count) async {
    await _writer.executeWithOwnerScopes(
      [owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
SELECT 'PH' || @prefix::text || lpad(to_hex(n), 11, '0'), @owner, 'Existing'
FROM generate_series(1, @count::int) AS n
'''),
      parameters: {
        'owner': owner,
        'count': count,
        'prefix': owner == _owner ? 'a' : 'b',
      },
    );
  }

  Future<void> seedPhantom({bool merged = false}) async {
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom
  (id, owner_id, display_name, emoji, merged_at, merged_user_id, merge_origin)
VALUES (
  @id, @owner, 'Anna K.', '🌻',
  CASE WHEN @merged::bool THEN now() END,
  CASE WHEN @merged THEN @other::text END,
  CASE WHEN @merged THEN 2 END
)
'''),
      parameters: {
        'id': _phantom,
        'owner': _owner,
        'merged': merged,
        'other': _other,
      },
    );
  }

  Future<void> seedPin() async {
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@owner)
'''),
      parameters: {'owner': _owner},
    );
    await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.constellation_anchor
  (id, viewer_id, phantom_id, x_units, y_units, coordinate_space_version, revision, placed_at)
VALUES (@id, @owner, @phantom, 1.25, 2.5, 1, 0, 'epoch')
'''),
      parameters: {
        'id': generateId('CA'),
        'owner': _owner,
        'phantom': _phantom,
      },
    );
  }

  Future<void> requireDeleteRelations() async {
    final rows = await _writer.execute('''
SELECT
  to_regclass('public.phantom_tag_member') IS NOT NULL AS tag_memberships,
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'invitation'
      AND column_name = 'phantom_id'
  ) AS phantom_invites
''');
    expect(
      rows.single.toColumnMap(),
      {'tag_memberships': true, 'phantom_invites': true},
      reason:
          'The delete cascade requires phantom_tag_member and invitation.phantom_id.',
    );
  }

  Future<String> seedTagMembership(String phantom) async {
    final tag = generateId('PT');
    return withPgOwnerScopes(_writer, [_owner], (tx) async {
      await tx.execute(
        Sql.named('''
INSERT INTO public.person_tag (id, owner_id, name, glyph, color, ord)
VALUES (@tag, @owner, 'Friends', 'F', 0, 0)
'''),
        parameters: {'tag': tag, 'owner': _owner},
      );
      final rows = await tx.execute(
        Sql.named('''
INSERT INTO public.phantom_tag_member
  (tag_id, owner_id, phantom_id, source, added_at)
VALUES (@tag, @owner, @phantom, 0, now())
RETURNING membership_id::text
'''),
        parameters: {'tag': tag, 'owner': _owner, 'phantom': phantom},
      );
      return rows.single.single! as String;
    });
  }

  Future<Result> tagMemberships(String id) => _writer.execute(
    Sql.named('''
SELECT phantom_id FROM public.phantom_tag_member WHERE membership_id = @id::uuid
'''),
    parameters: {'id': id},
  );

  Future<String> seedInvitation(String phantom) async {
    final rows = await _writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.invitation (user_id, phantom_id, addressee_name)
VALUES (@owner, @phantom, 'Anna K.') RETURNING id
'''),
      parameters: {'owner': _owner, 'phantom': phantom},
    );
    return rows.single.single! as String;
  }

  // Look up the original row by ID so clearing its phantom link would fail.
  Future<Result> invitations(String id) => _writer.execute(
    Sql.named('SELECT phantom_id FROM public.invitation WHERE id = @id'),
    parameters: {'id': id},
  );

  Future<void> seedInitMarker({required bool pending}) async {
    await _writer.execute(
      Sql.named('''
INSERT INTO public.person_field_first_seen_init (viewer_id, at, backfill_pending)
VALUES (@owner, '2026-01-02T00:00:00Z', @pending)
'''),
      parameters: {'owner': _owner, 'pending': pending},
    );
  }

  Future<int> phantomCount() async {
    final rows = await _writer.execute('SELECT count(*) FROM public.phantom');
    return rows.single.single! as int;
  }

  Future<int> activeCount(String owner) async {
    final rows = await _writer.execute(
      Sql.named('''
SELECT count(*) FROM public.phantom
WHERE owner_id = @owner AND merged_at IS NULL
'''),
      parameters: {'owner': owner},
    );
    return rows.single.single! as int;
  }

  Future<Map<String, Object?>?> phantom(String id) async {
    final rows = await _writer.execute(
      Sql.named('''
SELECT owner_id, display_name, emoji, merged_at, revision
FROM public.phantom WHERE id = @id
'''),
      parameters: {'id': id},
    );
    return rows.singleOrNull?.toColumnMap();
  }

  Future<List<Map<String, Object?>>> pins(String id) async {
    final rows = await _writer.execute(
      Sql.named('''
SELECT viewer_id, target_kind, phantom_id, x_units, y_units,
       coordinate_space_version, tombstone_at
FROM public.constellation_anchor WHERE target_id = @id OR phantom_id = @id
'''),
      parameters: {'id': id},
    );
    return [for (final row in rows) row.toColumnMap()];
  }

  Future<List<Map<String, Object?>>> initMarkers(String owner) async {
    final rows = await _writer.execute(
      Sql.named('''
SELECT at, backfill_pending
FROM public.person_field_first_seen_init WHERE viewer_id = @owner
'''),
      parameters: {'owner': owner},
    );
    return [for (final row in rows) row.toColumnMap()];
  }
}
