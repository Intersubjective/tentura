@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/policy/beacon_forward_policy.dart';

import '../../support/disposable_pg_target.dart';

/// m0211: `beacon_get_viewer_can_forward` is the SQL twin of
/// `BeaconForwardPolicy.canForward` for a Hasura session — an open-family
/// beacon whose policy is open, or whose author is the viewer.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.3.
const _author = 'Um0211author01';
const _viewer = 'Um0211viewer01';

/// `beacon_post_shape_ck`: statuses a Post may have.
const _postStatuses = {0, 2, 3};

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0211_VIEWER_CAN_FORWARD_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0211_vcf_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0211_VIEWER_CAN_FORWARD_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0211_vcf',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  test('the viewer-can-forward migration is registered', () {
    expect(
      migrationsForTesting.map((m) => m.version),
      contains('0211'),
    );
  });

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0210',
      );
      await _insertUser(session.writer, _author);
      await _insertUser(session.writer, _viewer);
      await migrateDbSchema(session.writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test('installs the viewer-can-forward function', () async {
      final rows = await session.writer.execute(
        'SELECT to_regprocedure('
        " 'public.beacon_get_viewer_can_forward(public.beacon, json)')::text",
      );
      expect(rows.single.single, isNotNull);
    });

    test('answers for a beacon that existed before the migration', () async {
      await _insertBeacon(
        session.writer,
        id: 'Bm0211upg0001',
        kind: 1,
        policy: 0,
      );
      expect(
        await _viewerCanForward(session.writer, 'Bm0211upg0001', _author),
        isTrue,
      );
      expect(
        await _viewerCanForward(session.writer, 'Bm0211upg0001', _viewer),
        isFalse,
      );
    });
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _insertUser(writer, _author);
      await _insertUser(writer, _viewer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'on an open-family status the four policy × viewer combinations are '
      'closed/author true, closed/other false, open/author true, '
      'open/other true',
      () async {
        await _insertBeacon(writer, id: 'Bm0211tbclosed1', kind: 1, policy: 0);
        await _insertBeacon(writer, id: 'Bm0211tbopen001', kind: 1, policy: 1);
        expect(
          {
            'closed policy, author': await _viewerCanForward(
              writer,
              'Bm0211tbclosed1',
              _author,
            ),
            'closed policy, other viewer': await _viewerCanForward(
              writer,
              'Bm0211tbclosed1',
              _viewer,
            ),
            'open policy, author': await _viewerCanForward(
              writer,
              'Bm0211tbopen001',
              _author,
            ),
            'open policy, other viewer': await _viewerCanForward(
              writer,
              'Bm0211tbopen001',
              _viewer,
            ),
          },
          {
            'closed policy, author': true,
            'closed policy, other viewer': false,
            'open policy, author': true,
            'open policy, other viewer': true,
          },
        );
      },
    );

    test('closed Post: the author can forward, a recipient cannot', () async {
      await _insertBeacon(writer, id: 'Bm0211closed01', kind: 1, policy: 0);
      expect(
        await _viewerCanForward(writer, 'Bm0211closed01', _author),
        isTrue,
      );
      expect(
        await _viewerCanForward(writer, 'Bm0211closed01', _viewer),
        isFalse,
      );
    });

    test('open Post: any viewer can forward', () async {
      await _insertBeacon(writer, id: 'Bm0211open0001', kind: 1, policy: 1);
      expect(
        await _viewerCanForward(writer, 'Bm0211open0001', _author),
        isTrue,
      );
      expect(
        await _viewerCanForward(writer, 'Bm0211open0001', _viewer),
        isTrue,
      );
    });

    test('Request: any viewer can forward while it is open', () async {
      await _insertBeacon(writer, id: 'Bm0211request1', kind: 0, policy: 1);
      expect(
        await _viewerCanForward(writer, 'Bm0211request1', _viewer),
        isTrue,
      );
    });

    test('a missing session user cannot forward a closed Post', () async {
      await _insertBeacon(writer, id: 'Bm0211anon0001', kind: 1, policy: 0);
      final rows = await writer.execute(
        "SELECT public.beacon_get_viewer_can_forward(b, '{}'::json) "
        "FROM public.beacon b WHERE b.id = 'Bm0211anon0001'",
      );
      expect(rows.single.single, isFalse);
    });

    test(
      'matches BeaconForwardPolicy.canForward for every status, policy and '
      'viewer',
      () async {
        var n = 0;
        for (final status in BeaconStatus.values) {
          for (final policy in BeaconForwardPolicyValue.values) {
            // `beacon_post_shape_ck` only admits Posts in statuses 0, 2 and 3,
            // so the non-open-family Post statuses (deleted, draft) are
            // exercised as Posts under both policies; the remaining
            // statuses (cancelled, wrapping up, closed, needs-more-help,
            // enough-help) exist only as Requests, which always have the
            // open policy.
            final kind = _postStatuses.contains(status.smallintValue)
                ? BeaconKind.post
                : BeaconKind.request;
            if (kind == BeaconKind.request &&
                policy != BeaconForwardPolicyValue.open) {
              continue;
            }
            final id = 'Bm0211tt${(n++).toString().padLeft(5, '0')}';
            await _insertBeacon(
              writer,
              id: id,
              kind: kind.value,
              policy: policy.value,
              status: status.smallintValue,
            );
            final entity = BeaconEntity(
              id: id,
              title: '',
              author: const UserEntity(id: _author),
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              status: status,
              kind: kind,
              forwardPolicy: policy,
            );
            for (final viewer in [_author, _viewer]) {
              expect(
                await _viewerCanForward(writer, id, viewer),
                BeaconForwardPolicy.canForward(
                  beacon: entity,
                  senderId: viewer,
                ),
                reason:
                    '${kind.name} in status ${status.name}, '
                    'policy ${policy.name}, '
                    'viewer ${viewer == _author ? 'author' : 'recipient'}',
              );
            }
          }
        }
      },
    );

    test('a finished Request cannot be forwarded even by its author', () async {
      await _insertBeacon(
        writer,
        id: 'Bm0211finish01',
        kind: 0,
        policy: 1,
        status: 6,
      );
      expect(
        await _viewerCanForward(writer, 'Bm0211finish01', _author),
        isFalse,
      );
    });

    test(
      'a deleted open-policy Post cannot be forwarded by its author',
      () async {
        await _insertBeacon(
          writer,
          id: 'Bm0211deleted1',
          kind: 1,
          policy: 1,
          status: 2,
        );
        expect(
          await _viewerCanForward(writer, 'Bm0211deleted1', _author),
          isFalse,
        );
      },
    );
  });
}

Future<bool> _viewerCanForward(
  Connection writer,
  String beaconId,
  String viewerId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT public.beacon_get_viewer_can_forward(b, '
      "json_build_object('x-hasura-user-id', @viewer::text)) "
      'FROM public.beacon b WHERE b.id = @id',
    ),
    parameters: {'id': beaconId, 'viewer': viewerId},
  );
  return rows.single.single! as bool;
}

Future<void> _insertUser(Connection writer, String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');

Future<void> _insertBeacon(
  Connection writer, {
  required String id,
  required int kind,
  required int policy,
  int status = 0,
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$id', '$_author', '${kind == 1 ? '' : 'Request'}', '', $status, $kind,
        $policy, false, ${status == 3 ? 'NULL' : 'now()'})
''');
