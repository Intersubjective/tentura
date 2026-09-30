@Tags(['pg'])
library;

import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// A2: `TrustLedgerRepository` record / retract / unretract / project.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_TRUST_LEDGER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_trust_ledger',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late TrustLedgerRepository repo;

  const a = 'UtlAlice0001';
  const b = 'UtlBob000001';
  const c = 'UtlCarol0001';
  const ids = [a, b, c];

  LedgerEvidence ev(
    String s,
    String o,
    String key, {
    TrustEvidenceKind kind = TrustEvidenceKind.helped,
    DateTime? occurredAt,
  }) => LedgerEvidence(
    subjectId: s,
    objectId: o,
    kind: kind,
    count: 2,
    sourceKey: key,
    occurredAt: occurredAt,
  );

  Future<int> rows(String key) async {
    final r = await db
        .customSelect(
          'SELECT count(*)::int AS c FROM public.trust_evidence '
          "WHERE source_key = '$key'",
        )
        .getSingle();
    return r.read<int>('c');
  }

  Future<double> targetW(String s, String o) async {
    final r = await db
        .customSelect(
          'SELECT coalesce(max(target_w), 0)::float8 AS t '
          "FROM public.user_trust_edge WHERE subject = '$s' AND object = '$o'",
        )
        .getSingle();
    return r.read<double>('t');
  }

  if (skipReason == false) {
    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      db = openDisposablePgDatabase(target);
      repo = TrustLedgerRepository(db);
      for (final id in ids) {
        await db.customStatement(
          '''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', '${pgTestPublicKey('tledg', ids.indexOf(id) + 1)}',
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
        );
      }
    });

    tearDown(() async {
      await db.customStatement(
        "DELETE FROM public.trust_evidence WHERE subject_user_id IN ('$a','$b','$c')",
      );
      await db.customStatement(
        "DELETE FROM public.user_trust_edge WHERE subject IN ('$a','$b','$c')",
      );
      await db.customStatement(
        "DELETE FROM public.trust_publish_queue WHERE subject_user_id IN ('$a','$b','$c')",
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: db);
    });
  }

  test('record twice with the same source_key yields one row', () async {
    await repo.record([ev(a, b, 'tl:dup')]);
    await repo.record([ev(a, b, 'tl:dup')]);
    expect(await rows('tl:dup'), 1);
    expect(await repo.exists('tl:dup'), isTrue);
    expect(await repo.exists('tl:missing'), isFalse);
  }, skip: skipReason);

  test('record projects the pair', () async {
    await repo.record([ev(a, b, 'tl:proj')]);
    expect(await targetW(a, b), greaterThan(0));
  }, skip: skipReason);

  test('retract drops the projection, unretract restores it', () async {
    await repo.record([ev(a, b, 'tl:rt')]);
    final live = await targetW(a, b);
    expect(live, greaterThan(0));

    await repo.retract('tl:rt');
    expect(await targetW(a, b), 0);

    await repo.unretract('tl:rt');
    expect(await targetW(a, b), closeTo(live, 1e-6));
  }, skip: skipReason);

  // Wraps trust_project_pair so every executed call is logged in call order;
  // the original keeps running underneath.
  Future<void> installCallLog() async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS public.tl_call_log '
      '(seq serial PRIMARY KEY, s text NOT NULL, o text NOT NULL)',
    );
    await db.customStatement('TRUNCATE public.tl_call_log');
    await db.customStatement(
      'ALTER FUNCTION public.trust_project_pair(text, text) '
      'RENAME TO trust_project_pair_orig',
    );
    await db.customStatement(r'''
CREATE FUNCTION public.trust_project_pair(p_subject text, p_object text)
    RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.tl_call_log (s, o) VALUES (p_subject, p_object);
  PERFORM public.trust_project_pair_orig(p_subject, p_object);
END;
$$
''');
  }

  Future<void> removeCallLog() async {
    await db.customStatement(
      'DROP FUNCTION IF EXISTS public.trust_project_pair(text, text)',
    );
    await db.customStatement(
      'ALTER FUNCTION public.trust_project_pair_orig(text, text) '
      'RENAME TO trust_project_pair',
    );
    await db.customStatement('DROP TABLE IF EXISTS public.tl_call_log');
  }

  Future<List<(String, String)>> projectionCalls() async {
    final log = await db
        .customSelect('SELECT s, o FROM public.tl_call_log ORDER BY seq')
        .get();
    return [for (final r in log) (r.read<String>('s'), r.read<String>('o'))];
  }

  test(
    'project calls trust_project_pair in sorted (subject, object) order',
    () async {
      await installCallLog();
      try {
        await repo.project([(b, c), (a, c), (a, b)]);
        expect(await projectionCalls(), [(a, b), (a, c), (b, c)]);
      } finally {
        await removeCallLog();
      }
    },
    skip: skipReason,
  );

  test('record projects distinct pairs in sorted order', () async {
    await installCallLog();
    try {
      await repo.record([
        ev(b, c, 'tl:s2'),
        ev(a, c, 'tl:s1'),
        ev(a, c, 'tl:s3'),
      ]);
      expect(await projectionCalls(), [(a, c), (b, c)]);
    } finally {
      await removeCallLog();
    }
  }, skip: skipReason);

  test('hasLiveUsefulForwardSince sees only live kind-5 rows', () async {
    final at = DateTime.utc(2026, 3, 1);
    await repo.record([
      ev(a, b, 'tl:uf', kind: TrustEvidenceKind.usefulForward, occurredAt: at),
    ]);
    expect(
      await repo.hasLiveUsefulForwardSince(a, b, DateTime.utc(2026, 2, 1)),
      isTrue,
    );
    expect(
      await repo.hasLiveUsefulForwardSince(a, b, DateTime.utc(2026, 4, 1)),
      isFalse,
    );
    await repo.retract('tl:uf');
    expect(
      await repo.hasLiveUsefulForwardSince(a, b, DateTime.utc(2026, 2, 1)),
      isFalse,
    );
  }, skip: skipReason);
}
