@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _owner = 'Uptcaseowner01';
const _other = 'Uptcaseother001';
const _person = 'Uptcaseperson01';

/// Own tag CRUD and restore over the real repository: validation, limits,
/// ownership, `clientOpId` idempotency and the "no names in errors or logs"
/// rule.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PEOPLE_TAGS_CASE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_tags_case',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('own person tags', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late PeopleTagsCase tags;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      final db = target.databaseEnv;
      await configureDependencies(
        Env(
          environment: Environment.dev,
          serverUri: Uri.parse('http://127.0.0.1:2080'),
          publicKey: Env.kJwtPublicKey,
          privateKey: Env.kJwtPrivateKey,
          pgHost: db.pgHost,
          pgPort: db.pgPort,
          pgDatabase: db.pgDatabase,
          pgUsername: db.pgUsername,
          pgPassword: db.pgPassword,
          publicOrigin: 'http://127.0.0.1:2080',
          workersCount: 1,
          printEnv: false,
          isDebugModeOn: false,
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      tags = getIt<PeopleTagsCase>();
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _other, _person]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    var opCounter = 0;
    String nextOp() => 'op-${opCounter++}';

    Future<PersonTag> create(
      String name, {
      String owner = _owner,
      String? glyph,
      int? color,
      String? opId,
    }) => tags.create(
      ownerId: owner,
      name: name,
      glyph: glyph,
      color: color,
      clientOpId: opId ?? nextOp(),
    );

    Future<PeopleTagsExceptionCode> codeOf(Future<Object?> call) async {
      try {
        await call;
      } on PeopleTagsException catch (e) {
        return (e.code as PeopleTagsExceptionCodes).exceptionCode;
      }
      fail('expected a PeopleTagsException');
    }

    Future<int> count(String table, [String where = 'true']) async =>
        (await writer.execute('SELECT count(*) FROM public.$table WHERE $where'))
                .single
                .first!
            as int;

    group('create', () {
      test('stores a trimmed name and defaults glyph and colour', () async {
        final tag = await create('  friends  ');

        expect(tag.name, 'friends');
        expect(tag.glyph, 'F');
        expect(tag.color, 0);
        expect(tag.ord, 1);
        expect(tag.id, startsWith('PT'));
        expect(await tags.list(ownerId: _owner), [tag]);
      });

      test('defaults the colour to the number of own tags modulo 8', () async {
        for (var i = 0; i < 9; i++) {
          final tag = await create('tag $i');
          expect(tag.color, i % 8);
          expect(tag.ord, i + 1);
        }
      });

      test('the first tag creates the revision row and later tags do not '
          'add another', () async {
        expect(await count('person_tag_revision'), 0);
        await create('one');
        expect(await count('person_tag_revision', "owner_id = '$_owner'"), 1);
        await create('two');
        expect(await count('person_tag_revision'), 1);
      });

      test('rejects names that are empty after trimming or longer than 32 '
          'characters', () async {
        for (final name in ['', '   ', 'x' * 33]) {
          expect(
            await codeOf(create(name)),
            PeopleTagsExceptionCode.invalidTag,
          );
        }
        expect(await create('x' * 32), isA<PersonTag>());
      });

      test('names are unique per owner ignoring case', () async {
        await create('Friends');

        expect(
          await codeOf(create('fRIENDS')),
          PeopleTagsExceptionCode.tagNameTaken,
        );
        expect(await create('Friends', owner: _other), isA<PersonTag>());
      });

      test('rejects glyphs that are empty, longer than 8 code units or '
          'contain whitespace', () async {
        for (final glyph in ['', 'abcdefghi', 'a b', ' ', 'a\n']) {
          expect(
            await codeOf(create('g ${glyph.length}', glyph: glyph)),
            PeopleTagsExceptionCode.invalidTag,
          );
        }
        expect(
          (await create('emoji', glyph: '👍🏽')).glyph,
          '👍🏽',
        );
      });

      test('rejects a colour outside 0..7', () async {
        for (final color in [-1, 8]) {
          expect(
            await codeOf(create('c$color', color: color)),
            PeopleTagsExceptionCode.invalidTag,
          );
        }
        expect((await create('c7', color: 7)).color, 7);
      });

      test('the 51st tag is refused and the 50th is accepted', () async {
        for (var i = 0; i < 50; i++) {
          await create('tag $i');
        }
        expect(
          await codeOf(create('one too many')),
          PeopleTagsExceptionCode.tagLimitReached,
        );
        expect(await count('person_tag', "owner_id = '$_owner'"), 50);
        expect(await create('other owner fine', owner: _other), isA<PersonTag>());
      });
    });

    group('update', () {
      test('renames, recolours and changes the glyph', () async {
        final tag = await create('Friends');

        final updated = await tags.update(
          ownerId: _owner,
          id: tag.id,
          name: 'Family',
          glyph: 'X',
          color: 5,
          clientOpId: nextOp(),
        );

        expect(updated.id, tag.id);
        expect(updated.name, 'Family');
        expect(updated.glyph, 'X');
        expect(updated.color, 5);
        expect(updated.ord, tag.ord);
      });

      test('renaming to a name used by another own tag is refused, '
          'renaming to the same name in another case is allowed', () async {
        final a = await create('Alpha');
        await create('Beta');

        expect(
          await codeOf(
            tags.update(
              ownerId: _owner,
              id: a.id,
              name: 'beta',
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNameTaken,
        );
        final recased = await tags.update(
          ownerId: _owner,
          id: a.id,
          name: 'ALPHA',
          clientOpId: nextOp(),
        );
        expect(recased.name, 'ALPHA');
      });

      test('moving a tag renumbers the order densely', () async {
        final a = await create('a');
        final b = await create('b');
        final c = await create('c');

        await tags.update(
          ownerId: _owner,
          id: c.id,
          ord: 1,
          clientOpId: nextOp(),
        );

        final listed = await tags.list(ownerId: _owner);
        expect(listed.map((t) => t.id), [c.id, a.id, b.id]);
        expect(listed.map((t) => t.ord), [1, 2, 3]);
      });

      test('another owner cannot see or edit the tag', () async {
        final tag = await create('Private');

        expect(
          await codeOf(
            tags.update(
              ownerId: _other,
              id: tag.id,
              name: 'Hijacked',
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        expect(await tags.list(ownerId: _other), isEmpty);
        expect((await tags.list(ownerId: _owner)).single.name, 'Private');
      });

      test('an unknown tag id is tagNotFound', () async {
        expect(
          await codeOf(
            tags.update(
              ownerId: _owner,
              id: 'PTmissing',
              name: 'x',
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
      });
    });

    group('delete and restore', () {
      Future<void> addMember(String tagId, int source) => writer.execute(
        Sql.named(
          'INSERT INTO public.person_tag_member '
          '(tag_id, owner_id, person_id, source) '
          'VALUES (@tag, @owner, @person, @source)',
        ),
        parameters: {
          'tag': tagId,
          'owner': _owner,
          'person': _person,
          'source': source,
        },
      );

      test('delete returns a snapshot with members and sources', () async {
        final tag = await create('Friends', glyph: 'Q', color: 3);
        await addMember(tag.id, 2);

        final snapshot = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: nextOp(),
        );

        expect(snapshot.tag, tag);
        expect(snapshot.memberIds, [_person]);
        expect(snapshot.sources, [2]);
        expect(await tags.list(ownerId: _owner), isEmpty);
        expect(await count('person_tag_member'), 0);
      });

      test('restore recreates the tag with the same id and its members',
          () async {
        final tag = await create('Friends', glyph: 'Q', color: 3);
        await addMember(tag.id, 2);
        final snapshot = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: nextOp(),
        );

        final restored = await tags.restore(
          ownerId: _owner,
          snapshot: snapshot,
          clientOpId: nextOp(),
        );

        expect(restored.id, tag.id);
        expect(restored.name, 'Friends');
        expect(restored.glyph, 'Q');
        expect(restored.color, 3);
        expect(await tags.list(ownerId: _owner), [restored]);
        expect(
          await count('person_tag_member', "tag_id = '${tag.id}'"),
          1,
        );
      });

      test('restore fails with tagNameTaken when the name was reused',
          () async {
        final tag = await create('Friends');
        final snapshot = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: nextOp(),
        );
        await create('friends');

        expect(
          await codeOf(
            tags.restore(
              ownerId: _owner,
              snapshot: snapshot,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNameTaken,
        );
      });

      test('another owner cannot delete the tag', () async {
        final tag = await create('Friends');

        expect(
          await codeOf(
            tags.delete(ownerId: _other, id: tag.id, clientOpId: nextOp()),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        expect(await tags.list(ownerId: _owner), hasLength(1));
      });
    });

    group('idempotency by clientOpId', () {
      test('a repeated create returns the stored result and writes once',
          () async {
        final first = await create('Friends', opId: 'same-op');
        final second = await create('Friends', opId: 'same-op');

        expect(second, first);
        expect(await count('person_tag'), 1);
      });

      test('the same clientOpId with a changed payload is opIdReused',
          () async {
        await create('Friends', opId: 'same-op');

        expect(
          await codeOf(create('Family', opId: 'same-op')),
          PeopleTagsExceptionCode.opIdReused,
        );
        expect(await count('person_tag'), 1);
      });

      test('a repeated update, delete and restore replay without changing '
          'anything again', () async {
        final tag = await create('Friends');
        final updated = await tags.update(
          ownerId: _owner,
          id: tag.id,
          color: 4,
          clientOpId: 'upd',
        );
        expect(
          await tags.update(
            ownerId: _owner,
            id: tag.id,
            color: 4,
            clientOpId: 'upd',
          ),
          updated,
        );

        final snapshot = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: 'del',
        );
        final replayedDelete = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: 'del',
        );
        expect(replayedDelete.tag, snapshot.tag);

        final restored = await tags.restore(
          ownerId: _owner,
          snapshot: snapshot,
          clientOpId: 'res',
        );
        expect(
          await tags.restore(
            ownerId: _owner,
            snapshot: snapshot,
            clientOpId: 'res',
          ),
          restored,
        );
        expect(await tags.list(ownerId: _owner), [restored]);
      });

      test('the same clientOpId from another owner is independent', () async {
        final mine = await create('Friends', opId: 'shared');
        final theirs = await create('Friends', owner: _other, opId: 'shared');

        expect(theirs.id, isNot(mine.id));
      });
    });

    group('privacy', () {
      test('exception descriptions and log lines never contain a tag name '
          'or glyph', () async {
        const secretName = 'Zorblax-secret-name';
        const secretGlyph = '☃';
        final records = <LogRecord>[];
        final previousLevel = Logger.root.level;
        Logger.root.level = Level.ALL;
        final sub = Logger.root.onRecord.listen(records.add);
        addTearDown(() async {
          await sub.cancel();
          Logger.root.level = previousLevel;
        });

        final tag = await create(secretName, glyph: secretGlyph);
        final failures = <PeopleTagsException>[];
        Future<void> collect(Future<Object?> call) async {
          try {
            await call;
          } on PeopleTagsException catch (e) {
            failures.add(e);
          }
        }

        await collect(create(secretName.toUpperCase()));
        await collect(create('x' * 40));
        await collect(create('ok', glyph: 'has space'));
        await collect(create(secretName, opId: 'reuse'));
        await collect(create('different', opId: 'reuse'));
        await collect(
          tags.update(
            ownerId: _other,
            id: tag.id,
            name: secretName,
            clientOpId: nextOp(),
          ),
        );
        final snapshot = await tags.delete(
          ownerId: _owner,
          id: tag.id,
          clientOpId: nextOp(),
        );
        await create(secretName.toLowerCase());
        await collect(
          tags.restore(
            ownerId: _owner,
            snapshot: snapshot,
            clientOpId: nextOp(),
          ),
        );

        expect(failures, isNotEmpty);
        for (final failure in failures) {
          expect(failure.description, isNot(contains(secretName)));
          expect(failure.description.toLowerCase(),
              isNot(contains(secretName.toLowerCase())));
          expect(failure.description, isNot(contains(secretGlyph)));
          expect(failure.toString(), isNot(contains(secretGlyph)));
        }
        for (final record in records) {
          final line = '${record.message} ${record.error} ${record.stackTrace}';
          expect(line.toLowerCase(), isNot(contains(secretName.toLowerCase())));
          expect(line, isNot(contains(secretGlyph)));
        }
      });
    });
  });
}
