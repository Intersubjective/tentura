@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/post_write_guard_fixture.dart';

const _fact = 'Fpostguardfact';
const _otherPost = 'Bpostguardopen';
const _movingFact = 'Fpostguardmove';

/// Fact pinned by [guardOther] from [guardMessage] while the Post is writable.
const _insertFact =
    '''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, source_message_id)
VALUES ('$_fact', '$guardPost', 'Original fact', 0, '$guardOther',
        '$guardMessage')
''';

const _readFactText =
    "SELECT fact_text FROM public.beacon_fact_card WHERE id = '$_fact'";

/// Each UPDATE changes exactly one guarded column of [_fact].
const _guardedColumnUpdates = {
  'fact_text': "SET fact_text = 'Edited fact'",
  'visibility': 'SET visibility = 1',
  'status': 'SET status = 1',
  'revision_seq': 'SET revision_seq = 2',
  'last_edited_at': 'SET last_edited_at = now()',
  'other_editor_count': 'SET other_editor_count = 1',
  'history_truncated': 'SET history_truncated = true',
};

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_CARD_POST_GUARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_card_post_guard',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('Facts of an archived Post are read-only', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
    });

    Future<void> seed({int kind = 1}) async {
      await seedPostWriteGuard(writer, kind: kind);
    }

    Future<List<List<Object?>>> factRow() async => [
      for (final row in await writer.execute('''
SELECT fact_text, visibility::int, status::int, revision_seq,
       last_edited_at, other_editor_count::int, history_truncated
FROM public.beacon_fact_card WHERE id = '$_fact'
'''))
        row.toList(),
    ];

    setUp(seed);

    test('a fact can be pinned and edited in an open Post', () async {
      await writer.execute(_insertFact);
      for (final update in _guardedColumnUpdates.values) {
        await writer.execute(
          "UPDATE public.beacon_fact_card $update WHERE id = '$_fact'",
        );
      }
      expect(
        (await writer.execute(_readFactText)).single.single,
        'Edited fact',
      );
    });

    test('a fact can be pinned and edited in an open Request', () async {
      await seed(kind: 0);
      await writer.execute(_insertFact);
      await writer.execute(
        "UPDATE public.beacon_fact_card SET fact_text = 'Edited fact' "
        "WHERE id = '$_fact'",
      );
      expect(
        (await writer.execute(_readFactText)).single.single,
        'Edited fact',
      );
    });

    for (final state in ['closed', 'expired']) {
      group('in ${state == 'expired' ? 'an' : 'a'} $state Post', () {
        test('pinning a fact fails with post_archived', () async {
          await archiveGuardPost(writer, state);
          await expectLater(
            writer.execute(_insertFact),
            throwsA(postArchived),
          );
          expect(await writer.execute(_readFactText), isEmpty);
        });

        for (final MapEntry(key: column, value: update)
            in _guardedColumnUpdates.entries) {
          test('changing only $column fails with post_archived', () async {
            await writer.execute(_insertFact);
            final before = await factRow();
            await archiveGuardPost(writer, state);
            await expectLater(
              writer.execute(
                "UPDATE public.beacon_fact_card $update WHERE id = '$_fact'",
              ),
              throwsA(postArchived),
            );
            expect(await factRow(), before);
          });
        }

        test('moving a fact into it (changing only beacon_id) fails with '
            'post_archived', () async {
          await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_otherPost', '$guardAuthor', '', '', 0, 1, 1, false, now())
''');
          await writer.execute('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by)
VALUES ('$_movingFact', '$_otherPost', 'Elsewhere', 0, '$guardAuthor')
''');
          await archiveGuardPost(writer, state);
          await expectLater(
            writer.execute(
              "UPDATE public.beacon_fact_card SET beacon_id = '$guardPost' "
              "WHERE id = '$_movingFact'",
            ),
            throwsA(postArchived),
          );
          expect(
            (await writer.execute(
              'SELECT beacon_id FROM public.beacon_fact_card '
              "WHERE id = '$_movingFact'",
            )).single.single,
            _otherPost,
          );
        });

        test('its facts can still be read', () async {
          await writer.execute(_insertFact);
          await archiveGuardPost(writer, state);
          expect(
            (await writer.execute(
              'SELECT id, fact_text FROM public.beacon_fact_card '
              "WHERE beacon_id = '$guardPost'",
            )).map((row) => row.toList()),
            [
              [_fact, 'Original fact'],
            ],
          );
        });
      });
    }

    for (final state in ['closed', 'expired']) {
      group(
        'in ${state == 'expired' ? 'an' : 'a'} $state Post, columns outside the guard stay writable',
        () {
          setUp(() async {
            await writer.execute(_insertFact);
            await archiveGuardPost(writer, state);
          });

          test('pinned_by can change', () async {
            await writer.execute(
              "UPDATE public.beacon_fact_card SET pinned_by = '$guardMember' "
              "WHERE id = '$_fact'",
            );
            expect(
              (await writer.execute(
                "SELECT pinned_by FROM public.beacon_fact_card WHERE id = '$_fact'",
              )).single.single,
              guardMember,
            );
          });

          test('last_edited_by can change', () async {
            await writer.execute(
              "UPDATE public.beacon_fact_card SET last_edited_by = '$guardMember' "
              "WHERE id = '$_fact'",
            );
            expect(
              (await writer.execute(
                'SELECT last_edited_by FROM public.beacon_fact_card '
                "WHERE id = '$_fact'",
              )).single.single,
              guardMember,
            );
          });

          test('source_message_id can be cleared', () async {
            await writer.execute(
              'UPDATE public.beacon_fact_card SET source_message_id = NULL '
              "WHERE id = '$_fact'",
            );
            expect(
              (await writer.execute(
                'SELECT source_message_id FROM public.beacon_fact_card '
                "WHERE id = '$_fact'",
              )).single.single,
              isNull,
            );
          });

          test('deleting the user who pinned the fact succeeds and clears '
              'pinned_by', () async {
            await writer.execute(
              'DELETE FROM public."user" '
              "WHERE id = '$guardOther'",
            );
            expect(
              (await writer.execute(
                'SELECT fact_text, pinned_by FROM public.beacon_fact_card '
                "WHERE id = '$_fact'",
              )).single.toList(),
              ['Original fact', null],
            );
          });

          test('deleting the fact source message succeeds and clears '
              'source_message_id', () async {
            await writer.execute(
              "DELETE FROM public.beacon_room_message WHERE id = '$guardMessage'",
            );
            expect(
              (await writer.execute(
                'SELECT fact_text, source_message_id FROM public.beacon_fact_card '
                "WHERE id = '$_fact'",
              )).single.toList(),
              ['Original fact', null],
            );
          });

          test('fact revisions can still be recorded directly', () async {
            await writer.execute('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind)
VALUES ('$_fact', 2, 'Recorded later', '$guardAuthor', 1)
''');
            expect(
              (await writer.execute(
                'SELECT fact_text FROM public.beacon_fact_card_revision '
                "WHERE fact_card_id = '$_fact' AND seq = 2",
              )).single.single,
              'Recorded later',
            );
          });
        },
      );
    }

    test('internal fixtures may pin a fact in a closed Post', () async {
      await archiveGuardPost(writer, 'closed');
      await writer.runTx((tx) async {
        await tx.execute(
          'SET LOCAL tentura.discussion_internal_fixture '
          "= 'allow_non_general'",
        );
        await tx.execute(_insertFact);
      });
      expect(
        (await writer.execute(_readFactText)).single.single,
        'Original fact',
      );
    });
  });
}
