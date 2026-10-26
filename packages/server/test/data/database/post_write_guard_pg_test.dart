@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_outbox_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/post_write_guard_fixture.dart';
import '../../support/user_erasure_test_stack.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_WRITE_GUARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_write_guard',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  group('Post archive database write protection after schema upgrade', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late UserErasureTestStack erasure;

    setUpAll(() async {
      // Upgrade an existing lifetime-aware schema, including pre-existing room
      // rows, rather than proving only that a fresh schema works.
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0270',
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      await seedPostWriteGuard(writer);
      await archiveGuardPost(writer, 'expired');
      const existingDataQueries = {
        'Post': 'SELECT * FROM public.beacon ORDER BY id',
        'room messages': 'SELECT * FROM public.beacon_room_message ORDER BY id',
        'room poll': 'SELECT * FROM public.polling ORDER BY id',
        'poll variants': 'SELECT * FROM public.polling_variant ORDER BY id',
        'room baton': 'SELECT * FROM public.beacon_room_baton ORDER BY id',
      };
      Future<List<Map<String, dynamic>>> snapshot(String query) async => [
        for (final row in await writer.execute(query)) row.toColumnMap(),
      ];
      final existingData = {
        for (final entry in existingDataQueries.entries)
          entry.key: await snapshot(entry.value),
      };
      for (final entry in existingData.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: '${entry.key} seeded for upgrade',
        );
      }
      await migrateDbSchema(writer);
      // Assert before the per-test reset can hide deleted or modified rows.
      for (final entry in existingDataQueries.entries) {
        expect(
          await snapshot(entry.value),
          existingData[entry.key],
          reason: 'schema upgrade preserves existing ${entry.key} data',
        );
      }
      database = openDisposablePgDatabase(target);
      addTearDown(database.close);
      final logger = Logger('PostWriteGuardPgTest');
      erasure = buildUserErasureTestStack(
        db: database,
        userRepository: buildDefaultUserRepository(database),
        lifecycleEffects: BeaconLifecycleEffectsCase(
          BeaconHierarchyOutboxRepository(database),
          env: Env(environment: Environment.test),
          logger: logger,
        ),
        attention: TransactionalAttentionCase(
          MutatingUnitOfWork(database),
          AttentionDispatchRepository(database, logger),
        ),
      );
    });
    setUp(() => seedPostWriteGuard(writer));

    for (final lock in ['no_key_update', 'key_share']) {
      test('the $lock predicate permits Requests and live Posts and refuses '
          'expired, closed and deleted Posts', () async {
        Future<Object?> allowed() async => (await writer.execute(
          "SELECT public.beacon_post_write_allowed('$guardPost', '$lock')",
        )).single.single;
        expect(await allowed(), isTrue);
        for (final state in ['expired', 'closed', 'deleted']) {
          await archiveGuardPost(writer, state);
          expect(await allowed(), isFalse, reason: state);
        }
        await seedPostWriteGuard(writer, kind: 0);
        expect(await allowed(), isTrue);
        await archiveGuardPost(writer, 'closed');
        expect(await allowed(), isTrue);
      });
    }

    for (final probe in postWriteProbes) {
      group(probe.table, () {
        test('authored insert and update succeed in a live Post', () async {
          await writer.execute(probe.insert);
          expect(
            (await writer.execute(probe.read)).single.single,
            probe.original,
          );
          await writer.execute(probe.update);
          expect(
            (await writer.execute(probe.read)).single.single,
            probe.changed,
          );
        });
        for (final state in ['expired', 'closed']) {
          test(
            'authored insert into a $state Post fails with post_archived',
            () async {
              await archiveGuardPost(writer, state);
              await expectLater(
                writer.execute(probe.insert),
                throwsA(postArchived),
              );
              expect(await writer.execute(probe.read), isEmpty);
            },
          );
          test(
            'authored update in a $state Post fails with post_archived',
            () async {
              await writer.execute(probe.insert);
              await archiveGuardPost(writer, state);
              await expectLater(
                writer.execute(probe.update),
                throwsA(postArchived),
              );
              expect(
                (await writer.execute(probe.read)).single.single,
                probe.original,
              );
            },
          );
        }
        test(
          'explicit internal fixtures remain writable in a closed Post',
          () async {
            await archiveGuardPost(writer, 'closed');
            await writer.runTx((tx) async {
              await tx.execute(
                'SET LOCAL tentura.discussion_internal_fixture '
                "= 'allow_non_general'",
              );
              await tx.execute(probe.insert);
              await tx.execute(probe.update);
            });
            expect(
              (await writer.execute(probe.read)).single.single,
              probe.changed,
            );
            expect(
              (await writer.execute(
                'SELECT public.discussion_internal_fixture_allowed()',
              )).single.single,
              isFalse,
            );
          },
        );
      });
    }

    for (final state in ['expired', 'closed']) {
      test('a room-backed poll cannot be edited in a $state Post', () async {
        await archiveGuardPost(writer, state);
        await expectLater(
          writer.execute(
            "UPDATE public.polling SET question = 'Changed' WHERE id = '$guardPoll'",
          ),
          throwsA(postArchived),
        );
        expect(
          (await writer.execute(
            "SELECT question FROM public.polling WHERE id = '$guardPoll'",
          )).single.single,
          'Which?',
        );
      });

      test('system notices can still be inserted in a $state Post', () async {
        await archiveGuardPost(writer, state);
        for (final author in ['NULL', "'$guardAuthor'"]) {
          final rows = await writer.execute('''
INSERT INTO public.beacon_room_message
  (beacon_id, author_id, body, system_message_kind, system_payload)
VALUES ('$guardPost', $author, '', 5, '{"reason":"expired"}')
RETURNING id
''');
          expect(rows, hasLength(1));
        }
      });
    }

    test('a live room-backed poll can still be edited', () async {
      await writer.execute(
        "UPDATE public.polling SET question = 'Changed' WHERE id = '$guardPoll'",
      );
      expect(
        (await writer.execute(
          "SELECT question FROM public.polling WHERE id = '$guardPoll'",
        )).single.single,
        'Changed',
      );
    });

    test('polls without a room message remain writable', () async {
      await writer.execute('''
INSERT INTO public.polling (id, author_id, question)
VALUES ('Ppostguardstandalone', '$guardAuthor', 'Before')
''');
      await writer.execute('''
INSERT INTO public.polling_variant (id, polling_id, description)
VALUES ('Vpostguardstandalone', 'Ppostguardstandalone', 'One')
''');
      await writer.execute('''
INSERT INTO public.polling_act (author_id, polling_id, polling_variant_id, score)
VALUES ('$guardMember', 'Ppostguardstandalone', 'Vpostguardstandalone', 1)
''');
      await writer.execute(
        "UPDATE public.polling SET question = 'After' "
        "WHERE id = 'Ppostguardstandalone'",
      );
      await writer.execute(
        "UPDATE public.polling_variant SET description = 'Two' "
        "WHERE id = 'Vpostguardstandalone'",
      );
      await writer.execute(
        'UPDATE public.polling_act SET score = 2 '
        "WHERE polling_id = 'Ppostguardstandalone'",
      );
      expect(
        (await writer.execute(
          'SELECT score::int FROM public.polling_act '
          "WHERE polling_id = 'Ppostguardstandalone'",
        )).single.single,
        2,
      );
    });

    test(
      'closed Requests retain their message refusal and allow reactions',
      () async {
        await seedPostWriteGuard(writer, kind: 0);
        await archiveGuardPost(writer, 'closed');
        await expectLater(
          writer.execute(postWriteProbes.first.insert),
          throwsA(
            isA<ServerException>()
                .having((e) => e.code, 'SQLSTATE', '23514')
                .having((e) => e.message, 'message', 'discussion_read_only'),
          ),
        );
        final reaction = postWriteProbes[1];
        await writer.execute(reaction.insert);
        await writer.execute(reaction.update);
        expect(
          (await writer.execute(reaction.read)).single.single,
          reaction.changed,
        );
      },
    );

    for (final (kind, noun) in [(1, 'Post'), (0, 'Request')]) {
      test('deleting a replied-to message in a closed $noun keeps the reply '
          'with a NULL reference while body edits stay refused', () async {
        await seedPostWriteGuard(writer, kind: kind);
        await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, reply_to_message_id)
VALUES ('Rpostguardreply', '$guardPost', '$guardMember', 'Reply', '$guardMessage')
''');
        await archiveGuardPost(writer, 'closed');
        await writer.execute(
          "DELETE FROM public.beacon_room_message WHERE id = '$guardMessage'",
        );
        final reply = await writer.execute('''
SELECT body, reply_to_message_id FROM public.beacon_room_message
WHERE id = 'Rpostguardreply'
''');
        expect(reply, hasLength(1));
        expect(reply.single, ['Reply', null]);
        await expectLater(
          writer.execute(
            'UPDATE public.beacon_room_message '
            "SET body = 'Edited' WHERE id = 'Rpostguardreply'",
          ),
          throwsA(
            kind == 1
                ? postArchived
                : isA<ServerException>()
                      .having((e) => e.code, 'SQLSTATE', '23514')
                      .having(
                        (e) => e.message,
                        'message',
                        'discussion_read_only',
                      ),
          ),
        );
      });
    }

    Future<String> attachImage(String owner) async {
      final image =
          (await writer.execute(
                "INSERT INTO public.image (author_id) VALUES ('$owner') RETURNING id::text",
              )).single.single!
              as String;
      await writer.execute('''
INSERT INTO public.beacon_room_message_attachment (id, message_id, kind, image_id)
VALUES ('Apostguardimage', '$guardMessage', 0, '$image')
''');
      return image;
    }

    test('erasing an attachment owner in a closed Post clears the image '
        'reference and keeps the other author message', () async {
      final image = await attachImage(guardMember);
      await archiveGuardPost(writer, 'closed');
      expect(await erasure.erasureCase.deleteById(id: guardMember), isTrue);
      expect(
        await writer.execute(
          "SELECT id FROM public.image WHERE id = '$image'",
        ),
        isEmpty,
      );
      expect(
        (await writer.execute(
          'SELECT image_id FROM '
          "public.beacon_room_message_attachment WHERE id = 'Apostguardimage'",
        )).single.single,
        isNull,
      );
      expect(
        (await writer.execute(
          'SELECT author_id FROM public.beacon_room_message '
          "WHERE id = '$guardMessage'",
        )).single.single,
        guardAuthor,
      );
    });

    test(
      'erasing a Post author deletes their Post and its attached images',
      () async {
        final image = await attachImage(guardAuthor);
        await archiveGuardPost(writer, 'closed');
        expect(await erasure.erasureCase.deleteById(id: guardAuthor), isTrue);
        expect(
          (await writer.execute(
            'SELECT status::int FROM public.beacon '
            "WHERE id = '$guardPost'",
          )).single.single,
          2,
        );
        expect(
          await writer.execute(
            "SELECT id FROM public.image WHERE id = '$image'",
          ),
          isEmpty,
        );
        expect(
          await writer.execute(
            'SELECT id FROM public.beacon_room_message_attachment '
            'WHERE message_id IN (SELECT id FROM public.beacon_room_message '
            "WHERE beacon_id = '$guardPost')",
          ),
          isEmpty,
        );
      },
    );

    test('erasing the author of an already deleted Post with attachments '
        'succeeds', () async {
      final image = await attachImage(guardAuthor);
      await archiveGuardPost(writer, 'deleted');
      expect(await erasure.erasureCase.deleteById(id: guardAuthor), isTrue);
      expect(
        await writer.execute(
          "SELECT id FROM public.image WHERE id = '$image'",
        ),
        isEmpty,
      );
      expect(
        await writer.execute(
          'SELECT id FROM public.beacon_room_message '
          "WHERE beacon_id = '$guardPost'",
        ),
        isEmpty,
      );
    });

    test('erasing a selected baton taker in a closed Post preserves the baton '
        'and clears its taker', () async {
      await writer.execute('''
UPDATE public.beacon_room_baton
SET status = 1, taker_id = '$guardMember', selection_mode = 1, resolved_at = now()
WHERE id = '$guardBaton'
''');
      await writer.execute('''
INSERT INTO public.beacon_room_baton_candidate (baton_id, user_id, response)
VALUES ('$guardBaton', '$guardMember', 1)
''');
      await archiveGuardPost(writer, 'closed');
      expect(await erasure.erasureCase.deleteById(id: guardMember), isTrue);
      final row = (await writer.execute(
        'SELECT status::int, taker_id '
        "FROM public.beacon_room_baton WHERE id = '$guardBaton'",
      )).single;
      expect(row, [1, null]);
      expect(
        await writer.execute(
          'SELECT user_id FROM public.beacon_room_baton_candidate '
          "WHERE baton_id = '$guardBaton' AND user_id = '$guardMember'",
        ),
        isEmpty,
      );
    });

    test('deleting an owned image in a closed Post keeps the attachment '
        'with a NULL image reference', () async {
      final image = await attachImage(guardMember);
      await archiveGuardPost(writer, 'closed');
      await writer.execute(
        "DELETE FROM public.image WHERE id = '$image' "
        "AND author_id = '$guardMember'",
      );
      expect(
        (await writer.execute(
          'SELECT image_id FROM public.beacon_room_message_attachment '
          "WHERE id = 'Apostguardimage'",
        )).single.single,
        isNull,
      );
    });
  });
}
