@Tags(['pg'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';

import '../../support/disposable_pg_target.dart';

/// U10a — the sweep predicate and the read projection are one definition.
///
/// Until U10a, `AttentionDismissibleSql.prelude` and the repository's private
/// `_visibleWithSurfaceCte` / `eligible_pinned` were two hand-maintained
/// copies of the same idea. U10b moves that idea from `seen_at` to active
/// attention; it must move **once**.
///
/// This file is the proof that collapsing them changed nothing. The legacy
/// texts below are frozen verbatim from `a46c6b536` — the last commit where
/// two copies existed — and every test asserts the live shared definition
/// selects exactly the same rows as both of them. If a later unit needs to
/// change membership, these frozen copies go stale deliberately and the
/// expectations here are rewritten with the reason named; they are not to be
/// nudged to match an accident.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U10A_UNIFICATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_u10a_unification',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;

  setUpAll(() async {
    if (skipReason != false) return;
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    await _resetFixtures(writer);
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session);
  });

  group('the two pre-U10a definitions select the same rows', () {
    test('legacy sweep prelude == legacy repository CTE (visible + surface)', () async {
      expect(
        await _visibleRows(writer, _legacySweepPrelude),
        await _visibleRows(writer, _legacyRepositoryVisibleCte),
        reason:
            'addition 1: the sweep and the feed must already agree before the '
            'two copies are collapsed onto one',
      );
    });

    test('legacy sweep prelude == legacy repository CTE (scope)', () async {
      expect(
        await _scopeRows(writer, _legacySweepPrelude),
        await _scopeRows(writer, _legacyRepositoryVisibleCte),
      );
    });

    test('live shared definition == both legacy copies', () async {
      final live = await _visibleRows(writer, AttentionDismissibleSql.prelude);
      expect(live, await _visibleRows(writer, _legacySweepPrelude));
      expect(live, await _visibleRows(writer, _legacyRepositoryVisibleCte));

      final liveScope = await _scopeRows(writer, AttentionDismissibleSql.prelude);
      expect(liveScope, await _scopeRows(writer, _legacySweepPrelude));
      expect(liveScope, await _scopeRows(writer, _legacyRepositoryVisibleCte));
    });

    test('live eligible_pinned == the legacy grouping copy', () async {
      expect(
        await _pinnedRows(writer, AttentionDismissibleSql.prelude),
        await _pinnedRows(
          writer,
          '$_legacyRepositoryVisibleCte,\n$_legacyGroupingEligiblePinned',
        ),
      );
    });
  }, skip: skipReason);

  group('the shared definition is load-bearing for both consumers', () {
    /// Addition 2. A unification where only one consumer notices a change is
    /// a shared *name*, not shared logic. So loosen the shared definition —
    /// drop the surface split, the one clause both sides lean on — and
    /// require that the sweep's member set **and** the feed's per-surface
    /// counts both move.
    String loosened(String prelude) => prelude.replaceAll(
      "      THEN 'myWork'",
      "      THEN 'activity'",
    );

    test('loosening it changes the sweep member set', () async {
      final strict = await _dismissibleReceipts(
        writer,
        AttentionDismissibleSql.prelude,
      );
      final loose = await _dismissibleReceipts(
        writer,
        loosened(AttentionDismissibleSql.prelude),
      );
      expect(strict, isNot(equals(loose)));
      expect(
        loose,
        containsAll(strict),
        reason: 'loosening only ever adds members',
      );
      expect(
        loose,
        contains(_ownedReceiptId),
        reason:
            'a My Desk receipt becomes sweepable the moment the surface split '
            'stops holding — that is what the sweep depends on',
      );
    });

    test('loosening it changes the feed per-surface counts', () async {
      final strict = await _surfaceCounts(
        writer,
        AttentionDismissibleSql.prelude,
      );
      final loose = await _surfaceCounts(
        writer,
        loosened(AttentionDismissibleSql.prelude),
      );
      expect(strict, isNot(equals(loose)));
      expect(
        strict['myWork'],
        isNonZero,
        reason: 'the fixture must actually exercise the My Desk surface',
      );
      expect(loose['myWork'] ?? 0, 0);
    });
  }, skip: skipReason);

  group('one source, structurally', () {
    test('attention_repository.dart no longer spells the CTE out', () {
      final source = File(
        'lib/data/repository/attention_repository.dart',
      ).readAsStringSync();
      // Assert on the boolean, not the string: a failing `contains` matcher
      // would print the whole repository file into the test output.
      expect(
        source.contains('visible_raw AS ('),
        isFalse,
        reason:
            'U10a: the visible/surface CTE lives in AttentionDismissibleSql. '
            'A second copy here is the drift U10b would silently inherit.',
      );
      expect(
        source.contains('eligible_pinned AS ('),
        isFalse,
        reason: 'same for the pinned decision zone',
      );
    });
  });
}

const _viewerId = 'Uu10aunif01';
const _authorId = 'Uu10aunif02';
const _ownedBeaconId = 'Bu10aunifown';
const _forwardedBeaconId = 'Bu10auniffwd';
const _obligationBeaconId = 'Bu10aunifobl';
const _ownedReceiptId = 'Nu10aunifown';

/// Frozen at `a46c6b536`: `AttentionRepository._visibleWithSurfaceCte`.
const _legacyRepositoryVisibleCte = r'''
visible_raw AS (
  SELECT outbox.*, authorized.tombstone_copy
  FROM public.visible_attention_receipts($1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
scope AS (
  SELECT beacon_id FROM public.responsibility_scope_base_beacons($1)
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
)''';

/// Frozen at `a46c6b536`: the `eligible_pinned` half of
/// `AttentionRepository._activityGroupingCtes`.
const _legacyGroupingEligiblePinned = r'''
eligible_pinned AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  WHERE ii.user_id = $1
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.status = 0
    AND public.beacon_can_read_content(ii.beacon_id, $1)
    AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
)''';

/// Frozen at `a46c6b536`: `AttentionDismissibleSql.prelude`.
const _legacySweepPrelude = r'''
visible_raw AS (
  SELECT outbox.*
  FROM public.visible_attention_receipts($1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
scope AS (
  SELECT beacon_id FROM public.responsibility_scope_base_beacons($1)
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
),
eligible_pinned AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  WHERE ii.user_id = $1
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.status = 0
    AND public.beacon_can_read_content(ii.beacon_id, $1)
    AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
)''';

Future<List<String>> _visibleRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT id, surface FROM visible ORDER BY id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) '${row[0]}|${row[1]}'];
}

Future<List<String>> _scopeRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT beacon_id FROM scope ORDER BY beacon_id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) row.first! as String];
}

Future<List<String>> _pinnedRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT beacon_id FROM eligible_pinned ORDER BY beacon_id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) row.first! as String];
}

Future<List<String>> _dismissibleReceipts(
  Connection writer,
  String prelude,
) async {
  final rows = await writer.execute(
    '''
WITH $prelude,
${AttentionDismissibleSql.dismissibleReceipts}
SELECT receipt_id FROM activity_optional_dismissible ORDER BY receipt_id
''',
    parameters: [_viewerId],
  );
  return [for (final row in rows) row.first! as String];
}

Future<Map<String, int>> _surfaceCounts(
  Connection writer,
  String prelude,
) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT surface, COUNT(*)::int FROM visible GROUP BY surface
''',
    parameters: [_viewerId],
  );
  return {
    for (final row in rows) row[0]! as String: row[1]! as int,
  };
}

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@ownedId, @viewerId, 'Owned', 'Owned request', 0),
  (@forwardedId, @authorId, 'Forwarded', 'Forwarded request', 0),
  (@obligationId, @authorId, 'Obligation', 'Obligation request', 0)
'''),
    parameters: {
      'ownedId': _ownedBeaconId,
      'forwardedId': _forwardedBeaconId,
      'obligationId': _obligationBeaconId,
      'viewerId': _viewerId,
      'authorId': _authorId,
    },
  );
  for (final entry in const [
    ('Fu10aunif01', _forwardedBeaconId),
    ('Fu10aunif02', _obligationBeaconId),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
      parameters: {
        'id': entry.$1,
        'beaconId': entry.$2,
        'senderId': _authorId,
        'recipientId': _viewerId,
      },
    );
  }
  // One receipt per surface arm: owned Request (scope base), forwarded
  // Request (activity + pinned decision zone), and a Request pulled into
  // scope by a live obligation on it.
  await _insertReceipt(writer, id: _ownedReceiptId, beaconId: _ownedBeaconId);
  await _insertReceipt(
    writer,
    id: 'Nu10auniffwd',
    beaconId: _forwardedBeaconId,
  );
  await _insertReceipt(
    writer,
    id: 'Nu10aunifobl',
    beaconId: _obligationBeaconId,
    requiresAction: true,
  );
  await _insertReceipt(
    writer,
    id: 'Nu10aunifopt',
    beaconId: _obligationBeaconId,
  );
  await _insertReceipt(writer, id: 'Nu10aunifprf', beaconId: null);
}

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String? beaconId,
  bool requiresAction = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey, now(),
  @beaconId, @sourceEventKey,
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy,
  @requiresAction, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'destinationKind': beaconId == null ? 'profile' : 'beacon',
    'presentationKey': beaconId == null
        ? 'mutual_connection_formed'
        : 'request_status_changed',
    'accessPolicy': beaconId == null ? 'profile' : 'beacon_content',
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);
