@Tags(['pg', 'mr'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_geometry.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/domain/use_case/constellation_tag_magnet_case.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _viewer = 'Uwideplaceview1';
const _peer = 'Uwideplacepeer1';

/// The widened bound shared by the client, the server and the database CHECK.
const _bound = kConstellationCoordinateMaxUnits;

/// Placing a node or a tag magnet past the old ±10 limit goes through the
/// server's own placement use cases into a real database and reads back as
/// placed; past the shared bound the use cases answer with the typed
/// coordinate error, never a raw check violation from Postgres.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_WIDE_RANGE_PLACEMENT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_wide_place',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Placing past the old ±10 limit', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late ConstellationAnchorCase anchors;
    late ConstellationTagMagnetCase magnets;
    late PeopleTagsCase tags;
    var opCounter = 0;

    String nextOp() => 'wide-op-${opCounter++}';

    Future<ConstellationExceptionCode> constellationCodeOf(
      Future<Object?> Function() call,
    ) async {
      try {
        await call();
      } on ConstellationException catch (e) {
        return (e.code as ConstellationExceptionCodes).exceptionCode;
      } on ServerException catch (e) {
        fail(
          'expected the typed coordinate error, got a raw Postgres error '
          '(SQLSTATE ${e.code}, ${e.constraintName ?? e.message})',
        );
      }
      fail('expected a ConstellationException');
    }

    Future<AnchorApplyBatchResult> placePeer(double x, double y) =>
        anchors.apply(
          viewerId: _viewer,
          ops: [
            anchors.parseOp(
              viewerId: _viewer,
              clientOpId: nextOp(),
              kindWire: AnchorOpKind.upsert.wireValue,
              targetKindWire: 'PERSON',
              targetId: _peer,
              xUnits: x,
              yUnits: y,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
          ],
        );

    Future<List<double>> storedPeerPosition() async {
      final row = await writer.execute(
        Sql.named(
          'SELECT x_units, y_units FROM public.constellation_anchor '
          'WHERE viewer_id = @viewer AND person_id = @peer',
        ),
        parameters: {'viewer': _viewer, 'peer': _peer},
      );
      return [row.single[0]! as double, row.single[1]! as double];
    }

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
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
      anchors = getIt<ConstellationAnchorCase>();
      magnets = getIt<ConstellationTagMagnetCase>();
      tags = getIt<PeopleTagsCase>();
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      await writer.execute(
        'TRUNCATE public.constellation_anchor, '
        'public.constellation_anchor_cursor, '
        'public.constellation_anchor_op_log CASCADE',
      );
      for (final id in [_viewer, _peer]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key, '
            'created_at, updated_at) VALUES (@id, @id, @key, '
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$_viewer', '$_peer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$_peer', '$_viewer', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');
    });

    test(
      'a person anchored at (11, -11) is stored and reads back there',
      () async {
        final result = await placePeer(11, -11);

        final op = result.results.single;
        expect(op.status, AnchorOpStatus.ok, reason: op.reason);
        expect(op.anchor?.position.xUnits, 11);
        expect(op.anchor?.position.yUnits, -11);
        expect(await storedPeerPosition(), [11.0, -11.0]);
        // Written by the batch placement function
        // constellation_anchor_apply_ops, which logs each accepted operation.
        final logged = await writer.execute(
          Sql.named(
            'SELECT count(*)::int FROM public.constellation_anchor_op_log '
            'WHERE viewer_id = @viewer',
          ),
          parameters: {'viewer': _viewer},
        );
        expect(logged.single.single, 1);
      },
    );

    test('a person anchored at the shared bound is stored there', () async {
      final result = await placePeer(_bound, -_bound);

      final op = result.results.single;
      expect(op.status, AnchorOpStatus.ok, reason: op.reason);
      expect(await storedPeerPosition(), [_bound, -_bound]);
    });

    test(
      'an anchor past the shared bound gets the typed coordinate error and '
      'stores nothing',
      () async {
        expect(
          await constellationCodeOf(() => placePeer(_bound + 1, 0)),
          ConstellationExceptionCode.invalidCoordinates,
        );
        expect(
          await constellationCodeOf(() => placePeer(0, -(_bound + 1))),
          ConstellationExceptionCode.invalidCoordinates,
        );
        final count = await writer.execute(
          'SELECT count(*)::int FROM public.constellation_anchor',
        );
        expect(count.single.single, 0);
      },
    );

    test(
      'a tag magnet placed at (11, -11) is stored and listed there',
      () async {
        final tag = await tags.create(
          ownerId: _viewer,
          name: 'Far away',
          clientOpId: nextOp(),
        );

        final magnet = await magnets.upsert(
          viewerId: _viewer,
          tagId: tag.id,
          xUnits: 11,
          yUnits: -11,
          clientOpId: nextOp(),
        );

        expect(magnet.xUnits, 11);
        expect(magnet.yUnits, -11);
        final listed = (await magnets.list(viewerId: _viewer)).single;
        expect(listed.xUnits, 11);
        expect(listed.yUnits, -11);
      },
    );

    test(
      'a tag magnet past the shared bound gets the typed coordinate error',
      () async {
        final tag = await tags.create(
          ownerId: _viewer,
          name: 'Too far',
          clientOpId: nextOp(),
        );

        expect(
          await constellationCodeOf(
            () => magnets.upsert(
              viewerId: _viewer,
              tagId: tag.id,
              xUnits: _bound + 1,
              yUnits: 0,
              clientOpId: nextOp(),
            ),
          ),
          ConstellationExceptionCode.invalidCoordinates,
        );
        expect(await magnets.list(viewerId: _viewer), isEmpty);
      },
    );
  });
}
