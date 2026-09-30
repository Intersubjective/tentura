@Tags(['pg'])
library;

import 'dart:math' as math;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// A1b (m0204): seeds trust kind 9 `supported_colleague` (Arch §4.1 row 9,
/// §5.9b) — see `docs/plans/episode-closure-implementation-steps.md`.
const _alice = 'Um0204pgalice01';
const _bob = 'Um0204pgbob0001';
const _allIds = [_alice, _bob];

const _kindSupportedColleague = 9;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0204_SUPPORT_EDGE_KIND_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0204_support_edge_kind',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('m0204 supported_colleague kind', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
      });

      setUp(() async {
        await _insertUsers(session.writer, _allIds);
      });

      tearDown(() async {
        await _cleanup(session.writer, _allIds);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'trust_kind_config has kind 9 with the specified parameters',
      () async {
        final rows = await session.writer.execute(
          'SELECT slug, polarity, half_life_s, k_sat, mix_weight, '
          'linear_window_s, counts_for_immunity '
          'FROM public.trust_kind_config WHERE kind = $_kindSupportedColleague',
        );
        expect(rows, hasLength(1));
        final row = rows.single;
        expect(row[0], 'supported_colleague');
        expect(row[1], 0);
        expect(row[2], isNull);
        expect((row[3]! as num).toDouble(), closeTo(1, 1e-9));
        expect((row[4]! as num).toDouble(), closeTo(0.1, 1e-9));
        expect((row[5]! as num).toDouble(), closeTo(15552000, 1e-6));
        expect(row[6], false);
      },
      skip: skipReason,
    );

    test(
      'count 1 at age 0 yields trust_w 0.05 and trust_recent 0',
      () async {
        await _insertEvidence(
          session.writer,
          count: 1,
          sourceKey: 'm0204:now',
        );
        final fold = await _foldPair(session.writer);
        expect(fold.trustW, closeTo(0.05, 1e-9));
        expect(fold.trustRecent, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'count 1 at 90 days yields trust_w 0.03333',
      () async {
        await _insertEvidence(
          session.writer,
          count: 1,
          sourceKey: 'm0204:90d',
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 90)),
        );
        final fold = await _foldPair(session.writer);
        expect(fold.trustW, closeTo(0.1 * 0.5 / 1.5, 1e-9));
        expect(fold.trustRecent, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'count 1 at 181 days yields trust_w 0',
      () async {
        await _insertEvidence(
          session.writer,
          count: 1,
          sourceKey: 'm0204:181d',
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 181)),
        );
        final fold = await _foldPair(session.writer);
        expect(fold.trustW, closeTo(0, 1e-9));
        expect(fold.trustRecent, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );

    test(
      'count 1/sqrt(2) at age 0 yields trust_w 0.04142',
      () async {
        await _insertEvidence(
          session.writer,
          count: 1 / math.sqrt(2),
          sourceKey: 'm0204:invsqrt2',
        );
        final fold = await _foldPair(session.writer);
        expect(fold.trustW, closeTo(0.04142, 1e-5));
        expect(fold.trustRecent, closeTo(0, 1e-9));
      },
      skip: skipReason,
    );
  });
}

typedef _FoldRow = ({double trustW, double trustRecent});

Future<void> _insertUsers(Connection writer, List<String> ids) async {
  for (final id in ids) {
    await writer.execute(
      Sql.named(
        '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @pk, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      ),
      parameters: {'id': id, 'pk': 'pk-$id'},
    );
  }
}

Future<_FoldRow> _foldPair(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT trust_w, trust_recent FROM trust_fold_pair(@s, @o)',
    ),
    parameters: {'s': _alice, 'o': _bob},
  );
  final row = rows.single;
  return (
    trustW: (row[0]! as num).toDouble(),
    trustRecent: (row[1]! as num).toDouble(),
  );
}

Future<void> _insertEvidence(
  Connection writer, {
  required double count,
  required String sourceKey,
  DateTime? occurredAt,
}) async {
  await writer.execute(
    Sql.named(
      '''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key, occurred_at
) VALUES (
  @id, @subject, @object, @kind, @count, @source_key,
  coalesce(@occurred_at, now())
)
''',
    ),
    parameters: {
      'id': 'T${sourceKey.hashCode.abs().toRadixString(16).padLeft(12, '0')}',
      'subject': _alice,
      'object': _bob,
      'kind': _kindSupportedColleague,
      'count': count,
      'source_key': sourceKey,
      'occurred_at': occurredAt,
    },
  );
}

Future<void> _cleanup(Connection writer, List<String> ids) async {
  final idList = ids.map((id) => "'$id'").join(', ');
  await writer.execute(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await writer.execute(
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await writer.execute(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await writer.execute('DELETE FROM public."user" WHERE id IN ($idList)');
}
