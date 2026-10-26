@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _owner = 'Utmgowner00001';
const _other = 'Utmgother00001';

/// A viewer's tag magnets on the Field: one `(x, y)` per own tag, written only
/// by the viewer through the use case, removed with the tag, invisible to
/// everyone else, and announced to the owner's other devices through the
/// `person_tag` realtime kind without leaking anything.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_TAG_MAGNET_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_tagmagnet',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('constellation tag magnets', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> subscription;
    late ConstellationTagMagnetCase magnets;
    late PeopleTagsCase tags;
    final notifications = <String>[];
    var opCounter = 0;

    String nextOp() => 'op-${opCounter++}';

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 200));

    Future<PersonTag> createTag(String name, {String owner = _owner}) =>
        tags.create(ownerId: owner, name: name, clientOpId: nextOp());

    Future<int> count([String where = 'true']) async =>
        (await writer.execute(
              'SELECT count(*) FROM public.constellation_tag_magnet '
              'WHERE $where',
            )).single.first!
            as int;

    Future<PeopleTagsExceptionCode> peopleCodeOf(Future<Object?> call) async {
      try {
        await call;
      } on PeopleTagsException catch (e) {
        return (e.code as PeopleTagsExceptionCodes).exceptionCode;
      }
      fail('expected a PeopleTagsException');
    }

    Future<ConstellationExceptionCode> constellationCodeOf(
      Future<Object?> call,
    ) async {
      try {
        await call;
      } on ConstellationException catch (e) {
        return (e.code as ConstellationExceptionCodes).exceptionCode;
      }
      fail('expected a ConstellationException');
    }

    Future<BigInt> ownerRevision() async => BigInt.parse(
      (await writer.execute(
        Sql.named(
          'SELECT revision FROM public.person_tag_revision '
          'WHERE owner_id = @owner',
        ),
        parameters: {'owner': _owner},
      )).single.single.toString(),
    );

    /// `person_tag` hints seen on `entity_changes`, optionally for one owner.
    List<Map<String, dynamic>> hints([String? owner]) => [
      for (final raw in notifications)
        if (jsonDecode(raw) as Map<String, dynamic> case final m
            when m['entity'] == 'person_tag')
          if (owner == null || m['id'] == owner) m,
    ];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      subscription = listener.channels['entity_changes'].listen(
        notifications.add,
      );
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
      magnets = getIt<ConstellationTagMagnetCase>();
      tags = getIt<PeopleTagsCase>();
    });

    tearDownAll(() async {
      await subscription.cancel();
      await listener.close();
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      for (final id in [_owner, _other]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
    });

    group('storage', () {
      test(
        'is keyed by viewer and tag and has the documented columns',
        () async {
          final columns = await writer.execute(
            'SELECT column_name FROM information_schema.columns '
            "WHERE table_schema = 'public' "
            "AND table_name = 'constellation_tag_magnet'",
          );
          expect(
            columns.map((r) => r.first).toSet(),
            containsAll([
              'viewer_id',
              'tag_id',
              'x_units',
              'y_units',
              'revision',
            ]),
          );

          final key = await writer.execute(
            'SELECT a.attname FROM pg_index i '
            'JOIN pg_attribute a ON a.attrelid = i.indrelid '
            'AND a.attnum = ANY (i.indkey) '
            "WHERE i.indrelid = 'public.constellation_tag_magnet'::regclass "
            'AND i.indisprimary',
          );
          expect(key.map((r) => r.first).toSet(), {'viewer_id', 'tag_id'});
        },
      );

      test('both foreign keys cascade on delete', () async {
        final rows = await writer.execute(
          'SELECT confrelid::regclass::text, confdeltype::text '
          'FROM pg_constraint '
          "WHERE conrelid = 'public.constellation_tag_magnet'::regclass "
          "AND contype = 'f'",
        );
        expect(
          {for (final r in rows) r[0]! as String: r[1]},
          {'person_tag': 'c', '"user"': 'c'},
        );
      });
    });

    group('own magnets', () {
      test('upsert creates a magnet that list returns for its owner', () async {
        final tag = await createTag('Neighbours');

        final created = await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 3.5,
          yUnits: -2.25,
          clientOpId: nextOp(),
        );

        expect(created.tagId, tag.id);
        expect(created.xUnits, 3.5);
        expect(created.yUnits, -2.25);
        final listed = await magnets.list(viewerId: _owner);
        expect(listed, [created]);
        expect(await count(), 1);
      });

      test(
        'a second upsert moves the same magnet and bumps its revision',
        () async {
          final tag = await createTag('Neighbours');
          final first = await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 1,
            yUnits: 1,
            clientOpId: nextOp(),
          );

          final moved = await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: -4,
            yUnits: 6,
            clientOpId: nextOp(),
          );

          expect(await count(), 1);
          expect(moved.xUnits, -4);
          expect(moved.yUnits, 6);
          expect(moved.revision, greaterThan(first.revision));
          expect((await magnets.list(viewerId: _owner)).single, moved);
        },
      );

      test('remove deletes only that tag magnet', () async {
        final kept = await createTag('Kept');
        final gone = await createTag('Gone');
        for (final tag in [kept, gone]) {
          await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 1,
            yUnits: 2,
            clientOpId: nextOp(),
          );
        }

        await magnets.remove(
          viewerId: _owner,
          tagId: gone.id,
          clientOpId: nextOp(),
        );

        expect(
          (await magnets.list(viewerId: _owner)).map((m) => m.tagId),
          [kept.id],
        );
      });

      test(
        'removing a tag without a magnet is a no-op, not an error',
        () async {
          final tag = await createTag('Plain');

          await magnets.remove(
            viewerId: _owner,
            tagId: tag.id,
            clientOpId: nextOp(),
          );

          expect(await count(), 0);
        },
      );

      test(
        'a repeated clientOpId replays the stored result without writing',
        () async {
          final tag = await createTag('Neighbours');
          const op = 'same-magnet-op';
          final first = await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 2,
            yUnits: 3,
            clientOpId: op,
          );
          await settle();
          notifications.clear();

          final replay = await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 2,
            yUnits: 3,
            clientOpId: op,
          );
          await settle();

          expect(replay, first);
          expect(hints(), isEmpty);
        },
      );

      test('a clientOpId reused with another payload is opIdReused', () async {
        final tag = await createTag('Neighbours');
        const op = 'reused-magnet-op';
        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 2,
          yUnits: 3,
          clientOpId: op,
        );

        expect(
          await peopleCodeOf(
            magnets.upsert(
              viewerId: _owner,
              tagId: tag.id,
              xUnits: 9,
              yUnits: 9,
              clientOpId: op,
            ),
          ),
          PeopleTagsExceptionCode.opIdReused,
        );
        expect((await magnets.list(viewerId: _owner)).single.xUnits, 2);
      });

      test('an unknown tag is tagNotFound and stores nothing', () async {
        expect(
          await peopleCodeOf(
            magnets.upsert(
              viewerId: _owner,
              tagId: 'PTnosuchtag',
              xUnits: 0,
              yUnits: 0,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        expect(await count(), 0);
      });

      test('non-finite or out-of-range coordinates are rejected', () async {
        final tag = await createTag('Neighbours');
        for (final (x, y) in [
          (double.nan, 0.0),
          (0.0, double.infinity),
          (1e9, 0.0),
          (0.0, -1e9),
        ]) {
          expect(
            await constellationCodeOf(
              magnets.upsert(
                viewerId: _owner,
                tagId: tag.id,
                xUnits: x,
                yUnits: y,
                clientOpId: nextOp(),
              ),
            ),
            ConstellationExceptionCode.invalidCoordinates,
            reason: '($x, $y)',
          );
        }
        expect(await count(), 0);
      });
    });

    group('deleting the tag', () {
      test('cascades its magnet and leaves the other magnets', () async {
        final doomed = await createTag('Doomed');
        final kept = await createTag('Kept');
        for (final tag in [doomed, kept]) {
          await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 1,
            yUnits: 1,
            clientOpId: nextOp(),
          );
        }

        await tags.delete(ownerId: _owner, id: doomed.id, clientOpId: nextOp());

        expect(await count("tag_id = '${doomed.id}'"), 0);
        expect(
          (await magnets.list(viewerId: _owner)).map((m) => m.tagId),
          [kept.id],
        );
      });

      test('erasing the owner removes every magnet', () async {
        final tag = await createTag('Neighbours');
        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );

        await writer.execute(
          "DELETE FROM public.\"user\" WHERE id = '$_owner'",
        );

        expect(await count(), 0);
      });
    });

    group('privacy', () {
      test('another user sees no magnets of the owner', () async {
        final tag = await createTag('Neighbours');
        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );

        expect(await magnets.list(viewerId: _other), isEmpty);
      });

      test("another user cannot place a magnet on the owner's tag", () async {
        final tag = await createTag('Neighbours');

        expect(
          await peopleCodeOf(
            magnets.upsert(
              viewerId: _other,
              tagId: tag.id,
              xUnits: 5,
              yUnits: 5,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        expect(await count(), 0);
      });

      test("another user cannot remove the owner's magnet", () async {
        final tag = await createTag('Neighbours');
        final mine = await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );

        expect(
          await peopleCodeOf(
            magnets.remove(
              viewerId: _other,
              tagId: tag.id,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );

        expect(await magnets.list(viewerId: _owner), [mine]);
      });

      test("another user cannot move the owner's magnet", () async {
        final tag = await createTag('Neighbours');
        final mine = await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );

        expect(
          await peopleCodeOf(
            magnets.upsert(
              viewerId: _other,
              tagId: tag.id,
              xUnits: 8,
              yUnits: 8,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );

        expect(await magnets.list(viewerId: _owner), [mine]);
      });
    });

    group('realtime', () {
      test(
        'an upsert sends one person_tag hint to the owner only, with a '
        'revision and no tag id, name or coordinates',
        () async {
          final tag = await createTag('Zebra Confidants');
          await settle();
          notifications.clear();

          await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 7.125,
            yUnits: -8.375,
            clientOpId: nextOp(),
          );
          await settle();

          final delivered = hints();
          expect(delivered, hasLength(1));
          final hint = delivered.single;
          expect(hint['id'], _owner);
          expect(hint['event'], 'update');
          expect(hint['user_ids'], [_owner]);
          expect(hint['revision'], isNotNull);
          final raw = notifications.single;
          for (final secret in [tag.id, 'Zebra', '7.125', '8.375']) {
            expect(
              raw,
              isNot(contains(secret)),
              reason: 'payload leaks $secret',
            );
          }
          expect(hints(_other), isEmpty);
        },
      );

      test('the hint carries a newer revision after every change', () async {
        final tag = await createTag('Neighbours');
        await settle();
        notifications.clear();

        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );
        await magnets.remove(
          viewerId: _owner,
          tagId: tag.id,
          clientOpId: nextOp(),
        );
        await settle();

        final revisions = [
          for (final h in hints(_owner)) BigInt.parse(h['revision'].toString()),
        ];
        expect(revisions, hasLength(2));
        expect(revisions.last, greaterThan(revisions.first));
      });

      test('removing a magnet sends one hint to the owner', () async {
        final tag = await createTag('Neighbours');
        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );
        await settle();
        notifications.clear();

        await magnets.remove(
          viewerId: _owner,
          tagId: tag.id,
          clientOpId: nextOp(),
        );
        await settle();

        expect(hints(), hasLength(1));
        expect(hints().single['user_ids'], [_owner]);
      });

      test('rejected writes from another user send nothing', () async {
        final tag = await createTag('Neighbours');
        await magnets.upsert(
          viewerId: _owner,
          tagId: tag.id,
          xUnits: 1,
          yUnits: 1,
          clientOpId: nextOp(),
        );
        await settle();
        notifications.clear();

        expect(
          await peopleCodeOf(
            magnets.upsert(
              viewerId: _other,
              tagId: tag.id,
              xUnits: 1,
              yUnits: 1,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        expect(
          await peopleCodeOf(
            magnets.remove(
              viewerId: _other,
              tagId: tag.id,
              clientOpId: nextOp(),
            ),
          ),
          PeopleTagsExceptionCode.tagNotFound,
        );
        await settle();

        expect(hints(), isEmpty);
      });

      test(
        'deleting a tag that has a magnet sends one hint to the owner',
        () async {
          final tag = await createTag('Neighbours');
          await magnets.upsert(
            viewerId: _owner,
            tagId: tag.id,
            xUnits: 1,
            yUnits: 1,
            clientOpId: nextOp(),
          );
          await settle();
          notifications.clear();

          await tags.delete(ownerId: _owner, id: tag.id, clientOpId: nextOp());
          await settle();

          expect(hints(), hasLength(1));
          expect(hints().single['user_ids'], [_owner]);
        },
      );

      group('inside one transaction', () {
        Future<void> insertMagnet(
          TxSession tx,
          String tagId,
          double x,
          double y,
        ) => tx.execute(
          Sql.named(
            'INSERT INTO public.constellation_tag_magnet '
            '(viewer_id, tag_id, x_units, y_units, revision) '
            'VALUES (@viewer, @tag, @x, @y, 1)',
          ),
          parameters: {'viewer': _owner, 'tag': tagId, 'x': x, 'y': y},
        );

        test(
          'several magnet changes are announced once, only after commit, '
          'with one revision step',
          () async {
            final a = await createTag('A');
            final b = await createTag('B');
            await settle();
            final revisionBefore = await ownerRevision();
            notifications.clear();

            await writer.runTx((tx) async {
              await insertMagnet(tx, a.id, 1, 1);
              await insertMagnet(tx, b.id, 2, 2);
              await tx.execute(
                Sql.named(
                  'UPDATE public.constellation_tag_magnet SET x_units = 9 '
                  'WHERE viewer_id = @viewer AND tag_id = @tag',
                ),
                parameters: {'viewer': _owner, 'tag': a.id},
              );
              await tx.execute(
                Sql.named(
                  'DELETE FROM public.constellation_tag_magnet '
                  'WHERE viewer_id = @viewer AND tag_id = @tag',
                ),
                parameters: {'viewer': _owner, 'tag': b.id},
              );
              await settle();
              expect(hints(), isEmpty, reason: 'nothing before commit');
            });
            await settle();

            final delivered = hints();
            expect(delivered, hasLength(1));
            expect(delivered.single['user_ids'], [_owner]);
            expect(await ownerRevision(), revisionBefore + BigInt.one);
            expect(
              BigInt.parse(delivered.single['revision'].toString()),
              await ownerRevision(),
            );
          },
        );

        test(
          'a magnet change together with a tag change is announced once',
          () async {
            final tag = await createTag('Neighbours');
            await settle();
            notifications.clear();

            await writer.runTx((tx) async {
              await insertMagnet(tx, tag.id, 1, 1);
              await tx.execute(
                Sql.named(
                  "UPDATE public.person_tag SET name = 'Renamed' "
                  'WHERE id = @tag',
                ),
                parameters: {'tag': tag.id},
              );
            });
            await settle();

            expect(hints(), hasLength(1));
          },
        );

        test('a rolled-back magnet change sends nothing', () async {
          final tag = await createTag('Neighbours');
          await settle();
          notifications.clear();

          await writer
              .runTx((tx) async {
                await insertMagnet(tx, tag.id, 1, 1);
                throw StateError('abort');
              })
              .then<void>((_) {}, onError: (Object _) {});
          await settle();

          expect(hints(), isEmpty);
          expect(await count(), 0);
        });
      });
    });
  });
}
