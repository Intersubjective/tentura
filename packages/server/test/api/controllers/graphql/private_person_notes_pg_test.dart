@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/use_case/auth_case.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/owner_graph_contention.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _owner = 'U000000000031';
const _other = 'U000000000032';
const _person = 'U000000000033';
const _unrelated = 'U000000000034';

const _firstPhantom = 'PH000000000099';
const _secondPhantom = 'PH000000000011';
const _othersPhantom = 'PH000000000022';
const _firstName = 'Zara from the library';
const _firstRenamed = 'Zara from book club';
const _secondName = 'Alina from the park';
const _othersName = 'Irina from the choir';

typedef _Subject = ({String? userId, String? phantomId});
typedef _Section = ({String body, String? phantomName});

const _personSubject = (userId: _person, phantomId: null);
const _phantomSubject = (userId: null, phantomId: _firstPhantom);
const _secondSubject = (userId: null, phantomId: _secondPhantom);
const _othersSubject = (userId: null, phantomId: _othersPhantom);
const _self = (userId: _owner, phantomId: null);
const _unrelatedSubject = (userId: _unrelated, phantomId: null);

const _subjectKinds = {
  'a Tentura account': _personSubject,
  'someone outside Tentura': _phantomSubject,
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_PERSON_NOTES_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_person_notes',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Private notes about people', () {
    late _Fixtures fixtures;
    late _NotesApi api;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });

      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await enforceOwnerScope(session);
      await session.writer.execute("SET tentura.owner_scope_enforce = 'on'");
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });

      fixtures = _Fixtures(session.writer);
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      await expectDefaultOwnerScopeEnforcement(getIt<TenturaDb>());
      api = _NotesApi((await getIt.getAsync<RootRouter>()).routeHandler());
    });

    setUp(() => fixtures.reset());

    for (final MapEntry(key: kind, value: subject) in _subjectKinds.entries) {
      test('an author can save, read and delete a note on $kind', () async {
        expect(await api.read(subject), isEmpty);

        await api.save(subject, 'Bring the spare key');
        expect(
          (await api.read(subject)).map((section) => section.body),
          ['Bring the spare key'],
        );

        await api.remove(subject);
        expect(await api.read(subject), isEmpty);
        expect(await fixtures.notes(), isEmpty);
      });

      test('editing a note on $kind advances its revision in place', () async {
        await api.save(subject, 'a');
        final first = (await fixtures.notes()).single;
        expect(first['body'], 'a');
        expect(first['revision'], isA<int>());
        expect(first['updated_at'], isA<DateTime>());

        await api.save(subject, 'b');
        final second = (await fixtures.notes()).single;
        expect(second['owner_id'], _owner);
        expect(second['subject_user_id'], subject.userId);
        expect(second['subject_phantom_id'], subject.phantomId);
        expect(second['body'], 'b');
        expect(second['revision'], greaterThan(first['revision']! as int));
        expect(
          (second['updated_at']! as DateTime).compareTo(
            first['updated_at']! as DateTime,
          ),
          greaterThanOrEqualTo(0),
        );
        expect((await api.read(subject)).single.body, 'b');
      });

      test(
        'saving identical text refreshes the note metadata on $kind',
        () async {
          const body = 'Bring the spare key';
          await api.save(subject, body);
          final (
            revision,
            updatedAt,
          ) = switch ((await fixtures.notes()).single) {
            {
              'revision': final int revision,
              'updated_at': final DateTime updatedAt,
            } =>
              (revision, updatedAt),
            _ => fail('Expected a stored revision and timestamp'),
          };

          await api.save(subject, body);

          final saved = (await fixtures.notes()).single;
          expect(saved['body'], body);
          expect(saved['revision'], greaterThan(revision));
          expect(
            saved['updated_at'],
            isA<DateTime>().having(
              (timestamp) => timestamp.isAfter(updatedAt),
              'later than the first save',
              isTrue,
            ),
          );
        },
      );

      test('the database allows only one note per author on $kind', () async {
        await fixtures.insertNote(subject, 'a');
        await expectLater(
          fixtures.insertNote(subject, 'b'),
          _sqlState('23505'),
        );
        expect((await fixtures.notes()).single['body'], 'a');
      });
    }

    test('the API preserves a note of exactly 4000 characters', () async {
      final body = 'Ж${'я' * 3998}Ё';

      await api.save(_personSubject, body);

      expect(await api.read(_personSubject), [(body: body, phantomName: null)]);
    });

    test(
      'the API rejects a 4001-character note and preserves the saved body',
      () async {
        await api.save(_personSubject, 'Keep this');

        final reply = await api.upsert(_personSubject, 'я' * 4001);

        _expectRejected(reply, 'personNoteUpsert');
        expect((await api.read(_personSubject)).single.body, 'Keep this');
      },
    );

    test('the API rejects writing a note about your own account', () async {
      await api.save(_personSubject, 'A note about somebody else');

      _expectRejected(
        await api.upsert(_self, 'About myself'),
        'personNoteUpsert',
      );

      expect((await fixtures.notes()).single['subject_user_id'], _person);
    });

    test('the database rejects a 4001-character body', () async {
      await expectLater(
        fixtures.insertNote(_personSubject, 'я' * 4001),
        _sqlState('23514'),
      );
    });

    for (final MapEntry(key: description, value: subject) in {
      'with neither kind of subject': (userId: null, phantomId: null),
      'with both kinds of subject': (userId: _person, phantomId: _firstPhantom),
      'about the author’s own account': _self,
    }.entries) {
      test('the database rejects a note $description', () async {
        await expectLater(
          fixtures.insertNote(subject, 'Note'),
          _sqlState('23514'),
        );
      });
    }

    test('a direct note write requires the author’s owner scope', () async {
      await expectLater(
        fixtures.insertNote(_personSubject, 'No owner scope', scoped: false),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            contains('Owner scope required for INSERT on public.person_note'),
          ),
        ),
      );
    });

    test(
      'two authors can manage separate private notes on the same account',
      () async {
        await api.save(_personSubject, 'A’s note');
        final first = (await fixtures.notes()).single;
        expect(await api.read(_personSubject, actor: _other), isEmpty);

        await api.save(_personSubject, 'B’s note', actor: _other);
        expect(
          (await api.read(_personSubject, actor: _other)).single.body,
          'B’s note',
        );
        expect((await api.read(_personSubject)).single.body, 'A’s note');
        expect(
          await fixtures.notes(),
          unorderedEquals([
            first,
            allOf(
              containsPair('owner_id', _other),
              containsPair('body', 'B’s note'),
            ),
          ]),
        );

        await api.remove(_personSubject, actor: _other);
        expect(await api.read(_personSubject, actor: _other), isEmpty);
        expect((await api.read(_personSubject)).single.body, 'A’s note');
        expect(await fixtures.notes(), [first]);
      },
    );

    test(
      'another author cannot read, write or delete notes on a private entry',
      () async {
        const body = 'A private reminder';
        await api.save(_phantomSubject, body);
        expect((await api.read(_phantomSubject)).single.body, body);
        await api.remove(_phantomSubject);
        await api.save(_phantomSubject, body);
        final before = (await fixtures.notes()).single;

        _expectUnavailable(
          await api.readReply(_phantomSubject, actor: _other),
          'personNote',
          privateBody: body,
        );
        _expectUnavailable(
          await api.upsert(_phantomSubject, 'Replace it', actor: _other),
          'personNoteUpsert',
          privateBody: body,
        );
        expect(await fixtures.notes(), [before]);
        _expectUnavailable(
          await api.delete(_phantomSubject, actor: _other),
          'personNoteDelete',
          privateBody: body,
        );
        expect(await fixtures.notes(), [before]);
        expect((await api.read(_phantomSubject)).single.body, body);
      },
    );

    test(
      'deleting a private entry removes its note and preserves unrelated notes',
      () async {
        await api.save(_phantomSubject, 'Remove with the entry');
        await api.save(_unrelatedSubject, 'Keep me', actor: _other);
        final preserved = (await fixtures.notes()).singleWhere(
          (row) => row['owner_id'] == _other,
        );

        await api.removePhantom(_firstPhantom);

        expect(await fixtures.notes(), [preserved]);
        expect(
          (await api.read(_unrelatedSubject, actor: _other)).single.body,
          'Keep me',
        );
      },
    );

    test(
      'erasing an account removes the notes that describe it for every author',
      () async {
        await api.save(_personSubject, 'Remove this from A');
        await api.save(_personSubject, 'Remove this from B', actor: _other);
        await api.save(_unrelatedSubject, 'Keep me', actor: _other);
        final preserved = (await fixtures.notes()).singleWhere(
          (row) => row['subject_user_id'] == _unrelated,
        );

        await api.eraseAccount(_person);

        expect(await fixtures.notes(), [preserved]);
        expect(
          (await api.read(_unrelatedSubject, actor: _other)).single.body,
          'Keep me',
        );
      },
    );

    test(
      'erasing an author removes their notes on accounts and private entries',
      () async {
        await api.save(_personSubject, 'Remove this account note');
        await api.save(_phantomSubject, 'Remove this private entry note');
        await api.save(_unrelatedSubject, 'Keep me', actor: _other);
        final preserved = (await fixtures.notes()).singleWhere(
          (row) => row['owner_id'] == _other,
        );

        await api.eraseAccount(_owner);

        expect(await fixtures.notes(), [preserved]);
        expect(
          (await api.read(_unrelatedSubject, actor: _other)).single.body,
          'Keep me',
        );
      },
    );

    group('Notes when linking a private entry to an account', () {
      setUp(() async {
        await fixtures.allowLinkToPerson(_owner);
        await fixtures.allowLinkToPerson(_other);
      });

      test(
        'the account note comes first, followed by notes with current names in link order',
        () async {
          await api.save(_personSubject, 'Account reminder');
          await api.save(_phantomSubject, 'First linked reminder');
          await api.save(_secondSubject, 'Second linked reminder');

          await api.renamePhantom(_firstPhantom, _firstRenamed);
          await api.link(_firstPhantom);
          await api.link(_secondPhantom);

          expect(await api.read(_personSubject), [
            (body: 'Account reminder', phantomName: null),
            (body: 'First linked reminder', phantomName: _firstRenamed),
            (body: 'Second linked reminder', phantomName: _secondName),
          ]);
        },
      );

      test('linking leaves each note on its original subject', () async {
        await api.save(_personSubject, 'Account reminder');
        await api.save(_phantomSubject, 'x');
        final before = await fixtures.notes();
        expect(before, hasLength(2));

        await api.link(_firstPhantom);

        expect(await fixtures.notes(), unorderedEquals(before));
        expect(await api.read(_personSubject), [
          (body: 'Account reminder', phantomName: null),
          (body: 'x', phantomName: _firstName),
        ]);
      });

      test(
        'unlinking restores the account-only view and preserves the entry note',
        () async {
          await api.save(_personSubject, 'Account reminder');
          await api.save(_phantomSubject, 'Entry reminder');
          await api.link(_firstPhantom);
          expect(await api.read(_personSubject), [
            (body: 'Account reminder', phantomName: null),
            (body: 'Entry reminder', phantomName: _firstName),
          ]);

          await api.unlink(_firstPhantom);

          expect(await api.read(_personSubject), [
            (body: 'Account reminder', phantomName: null),
          ]);
          expect(
            (await api.read(_phantomSubject)).single.body,
            'Entry reminder',
          );
        },
      );

      test(
        'editing a linked section changes only the note for that subject',
        () async {
          await api.save(_personSubject, 'Account reminder');
          await api.save(_phantomSubject, 'x');
          await api.link(_firstPhantom);
          final account = (await fixtures.notes()).singleWhere(
            (row) => row['subject_user_id'] == _person,
          );

          await api.save(_phantomSubject, 'y');
          final afterEntryEdit = await fixtures.notes();
          expect(
            afterEntryEdit.singleWhere(
              (row) => row['subject_user_id'] == _person,
            ),
            account,
          );
          final entry = afterEntryEdit.singleWhere(
            (row) => row['subject_phantom_id'] == _firstPhantom,
          );
          expect(entry['body'], 'y');
          expect(await api.read(_personSubject), [
            (body: 'Account reminder', phantomName: null),
            (body: 'y', phantomName: _firstName),
          ]);

          await api.save(_personSubject, 'Updated account reminder');
          expect(
            (await fixtures.notes()).singleWhere(
              (row) => row['subject_phantom_id'] == _firstPhantom,
            ),
            entry,
          );
          expect(await api.read(_personSubject), [
            (body: 'Updated account reminder', phantomName: null),
            (body: 'y', phantomName: _firstName),
          ]);
        },
      );

      test(
        'an account read includes only the reader’s own linked sections',
        () async {
          await api.save(_personSubject, 'Account reminder');
          await api.save(_phantomSubject, 'My linked reminder');
          await api.save(
            _othersSubject,
            'Their private reminder',
            actor: _other,
          );
          await api.link(_firstPhantom);
          await api.link(_othersPhantom, actor: _other);

          expect(await api.read(_personSubject, actor: _other), [
            (body: 'Their private reminder', phantomName: _othersName),
          ]);
          expect(await api.read(_personSubject), [
            (body: 'Account reminder', phantomName: null),
            (body: 'My linked reminder', phantomName: _firstName),
          ]);
        },
      );
    });
  }, skip: skip);
}

Matcher _sqlState(String code) => throwsA(
  isA<ServerException>().having((error) => error.code, 'SQLSTATE', code),
);

Object? _field(Map<String, Object?> reply, String name) =>
    (reply['data'] as Map<String, Object?>?)?[name];

void _expectRejected(Map<String, Object?> reply, String operation) {
  // Domain errors have numeric codes; validation and internal errors must
  // never stand in for a rejection of an otherwise valid request.
  expect(
    reply['errors'],
    contains(
      containsPair(
        'extensions',
        containsPair('code', allOf(matches(r'^\d+$'), isNot('1000'))),
      ),
    ),
    reason: jsonEncode(reply),
  );
  expect(_field(reply, operation), anyOf(isNull, isFalse));
}

void _expectUnavailable(
  Map<String, Object?> reply,
  String operation, {
  required String privateBody,
}) {
  expect(
    jsonEncode(reply),
    isNot(anyOf(contains(privateBody), contains(_firstName))),
  );
  if (reply['errors'] != null) {
    _expectRejected(reply, operation);
    return;
  }
  expect(
    reply['data'],
    containsPair(operation, anyOf(isNull, isFalse, equals(const []))),
    reason: jsonEncode(reply),
  );
}

final class _NotesApi {
  const _NotesApi(this._handler);

  final Handler _handler;

  Map<String, Object?> _variables(_Subject subject) => {
    'userId': ?subject.userId,
    'phantomId': ?subject.phantomId,
  };

  Future<Map<String, Object?>> readReply(
    _Subject subject, {
    String actor = _owner,
  }) => _post(
    r'''
query ReadNote($userId: String, $phantomId: String) {
  personNote(subjectUserId: $userId, subjectPhantomId: $phantomId) {
    body
    phantomName
  }
}
''',
    _variables(subject),
    actor: actor,
  );

  Future<List<_Section>> read(_Subject subject, {String actor = _owner}) async {
    final reply = await readReply(subject, actor: actor);
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    final sections = _field(reply, 'personNote')! as List<Object?>;
    return [
      for (final section in sections.cast<Map<String, Object?>>())
        (
          body: section['body']! as String,
          phantomName: section['phantomName'] as String?,
        ),
    ];
  }

  Future<Map<String, Object?>> upsert(
    _Subject subject,
    String body, {
    String actor = _owner,
  }) => _post(
    r'''
mutation SaveNote($userId: String, $phantomId: String, $body: String!) {
  personNoteUpsert(subjectUserId: $userId, subjectPhantomId: $phantomId, body: $body)
}
''',
    {..._variables(subject), 'body': body},
    actor: actor,
  );

  Future<void> save(
    _Subject subject,
    String body, {
    String actor = _owner,
  }) async {
    _expectSuccess(
      await upsert(subject, body, actor: actor),
      'personNoteUpsert',
    );
  }

  Future<Map<String, Object?>> delete(
    _Subject subject, {
    String actor = _owner,
  }) => _post(
    r'''
mutation RemoveNote($userId: String, $phantomId: String) {
  personNoteDelete(subjectUserId: $userId, subjectPhantomId: $phantomId)
}
''',
    _variables(subject),
    actor: actor,
  );

  Future<void> remove(_Subject subject, {String actor = _owner}) async {
    _expectSuccess(await delete(subject, actor: actor), 'personNoteDelete');
  }

  Future<void> renamePhantom(String phantomId, String name) async {
    final reply = await _post(
      r'mutation Rename($id: String!, $name: String!) { phantomUpdate(id: $id, name: $name) }',
      {'id': phantomId, 'name': name},
      actor: _owner,
    );
    _expectSuccess(reply, 'phantomUpdate');
  }

  Future<void> link(String phantomId, {String actor = _owner}) async {
    final reply = await _post(
      r'mutation Link($id: String!, $user: String!) { phantomLink(phantomId: $id, userId: $user) }',
      {'id': phantomId, 'user': _person},
      actor: actor,
    );
    _expectSuccess(reply, 'phantomLink');
  }

  Future<void> unlink(String phantomId) async {
    final reply = await _post(
      r'mutation Unlink($id: String!) { phantomUnmerge(phantomId: $id) }',
      {'id': phantomId},
      actor: _owner,
    );
    _expectSuccess(reply, 'phantomUnmerge');
  }

  Future<void> removePhantom(String phantomId) async {
    final reply = await _post(
      r'mutation RemovePerson($id: String!) { phantomDelete(id: $id) }',
      {'id': phantomId},
      actor: _owner,
    );
    _expectSuccess(reply, 'phantomDelete');
  }

  Future<void> eraseAccount(String actor) async {
    _expectSuccess(
      await _post('mutation { userDelete }', const {}, actor: actor),
      'userDelete',
    );
  }

  void _expectSuccess(Map<String, Object?> reply, String operation) {
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    expect(_field(reply, operation), isTrue, reason: jsonEncode(reply));
  }

  Future<Map<String, Object?>> _post(
    String query,
    Map<String, Object?> variables, {
    required String actor,
  }) async {
    final token = getIt<AuthCase>().issueAccessToken(actor).rawToken;
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1:2080/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }
}

final class _Fixtures {
  const _Fixtures(this.writer);

  final Connection writer;

  Future<void> reset() async {
    await writer.execute('TRUNCATE TABLE public."user" CASCADE');
    for (final (index, id) in [_owner, _other, _person, _unrelated].indexed) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('private-notes', index + 1),
        },
      );
    }
    // Creation order, id order and alphabetical order all differ from the
    // intended link order used by the read test.
    for (final (id, author, name) in [
      (_secondPhantom, _owner, _secondName),
      (_firstPhantom, _owner, _firstName),
      (_othersPhantom, _other, _othersName),
    ]) {
      await writer.executeWithOwnerScopes(
        [author],
        Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @author, @name)
'''),
        parameters: {'id': id, 'author': author, 'name': name},
      );
    }
  }

  Future<void> allowLinkToPerson(String actor) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@actor, @person, 1)
'''),
      parameters: {'actor': actor, 'person': _person},
    );
  }

  Future<Result> insertNote(
    _Subject subject,
    String body, {
    bool scoped = true,
  }) {
    final sql = Sql.named('''
INSERT INTO public.person_note (owner_id, subject_user_id, subject_phantom_id, body)
VALUES (@owner, @userId::text, @phantomId::text, @body)
''');
    final parameters = {
      'owner': _owner,
      'userId': subject.userId,
      'phantomId': subject.phantomId,
      'body': body,
    };
    return scoped
        ? writer.executeWithOwnerScopes([_owner], sql, parameters: parameters)
        : writer.execute(sql, parameters: parameters);
  }

  Future<List<Map<String, Object?>>> notes() async {
    final result = await writer.execute('''
SELECT owner_id, subject_user_id, subject_phantom_id, body, revision, updated_at
FROM public.person_note
''');
    return result.map((row) => row.toColumnMap()).toList();
  }
}
