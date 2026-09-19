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
    test(
      'legacy sweep prelude == legacy repository CTE (visible + surface)',
      () async {
        expect(
          await _visibleRows(writer, _legacySweepPrelude),
          await _visibleRows(writer, _legacyRepositoryVisibleCte),
          reason:
              'addition 1: the sweep and the feed must already agree before the '
              'two copies are collapsed onto one',
        );
      },
    );

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

      final liveScope = await _scopeRows(
        writer,
        AttentionDismissibleSql.prelude,
      );
      expect(liveScope, await _scopeRows(writer, _legacySweepPrelude));
      expect(liveScope, await _scopeRows(writer, _legacyRepositoryVisibleCte));
    });

    test('live eligible_pinned == the legacy grouping copy', () async {
      final live = await _pinnedRows(writer, AttentionDismissibleSql.prelude);
      expect(
        live,
        await _pinnedRows(
          writer,
          '$_legacyRepositoryVisibleCte,\n$_legacyGroupingEligiblePinned',
        ),
      );
      // Name the membership, not just the agreement: the fixture holds four
      // `inbox_item` rows and exactly one is an unanswered forward. The other
      // three are each excluded by a different clause — scope, readability,
      // and status/dismissal — so an accidental widening in U10b/U10c shows
      // up here as an extra beacon rather than as two empty sets agreeing.
      expect(live, [_forwardedBeaconId]);
    });
  }, skip: skipReason);

  group('the fixture reaches the rows the equivalence is about', () {
    /// Addition 3. A row that never reaches `visible` is an inert fixture,
    /// and an inert fixture is how a comparison quietly goes back to being
    /// vacuous. Each edge row is named here once.
    test(
      'the restricted tombstone is visible',
      () async {
        final live = await _visibleRows(
          writer,
          AttentionDismissibleSql.prelude,
        );
        expect(
          live,
          contains('Nu10auniftmb|activity'),
          reason:
              'a receipt whose access_policy is beacon_tombstone, on a deleted '
              'Request the viewer may read only as a tombstone',
        );
        // CHANGES IN U15R-e: the Request-less obligation is no longer
        // asserted here, because it is no longer storable. Asserting it
        // would be asserting a row the database refuses to hold.
        expect(
          await _scopeRows(writer, AttentionDismissibleSql.prelude),
          isNot(contains(_deletedBeaconId)),
          reason: 'the tombstone Request is not work the viewer owes anyone',
        );
      },
    );
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
const _answeredBeaconId = 'Bu10aunifans';
const _deletedBeaconId = 'Bu10aunifdel';
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

/// Every comparison in this file must have something to compare. Two empty
/// sets are always equal, so an equivalence that ran over nothing proves
/// nothing — the guard lives in the helpers so no future comparison can skip
/// it.
void _expectNonVacuous(Iterable<Object?> rows, String what) => expect(
  rows,
  isNotEmpty,
  reason: 'the fixture must exercise $what; an empty set matches anything',
);

Future<List<String>> _visibleRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT id, surface FROM visible ORDER BY id
''',
    parameters: [_viewerId],
  );
  final visible = [for (final row in rows) '${row[0]}|${row[1]}'];
  _expectNonVacuous(visible, 'the visible/surface projection');
  return visible;
}

Future<List<String>> _scopeRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT beacon_id FROM scope ORDER BY beacon_id
''',
    parameters: [_viewerId],
  );
  final scope = [for (final row in rows) row.first! as String];
  _expectNonVacuous(scope, 'the responsibility scope');
  return scope;
}

Future<List<String>> _pinnedRows(Connection writer, String prelude) async {
  final rows = await writer.execute(
    '''
WITH $prelude
SELECT beacon_id FROM eligible_pinned ORDER BY beacon_id
''',
    parameters: [_viewerId],
  );
  final pinned = [for (final row in rows) row.first! as String];
  // The one that was vacuous until this remediation: no `inbox_item` row
  // existed, so the unanswered-forward guarantee compared empty to empty.
  _expectNonVacuous(pinned, 'the pinned decision zone (unanswered forwards)');
  return pinned;
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
  final receipts = [for (final row in rows) row.first! as String];
  _expectNonVacuous(receipts, 'the sweep member set');
  return receipts;
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
  final counts = {
    for (final row in rows) row[0]! as String: row[1]! as int,
  };
  _expectNonVacuous(counts.keys, 'the per-surface counts');
  return counts;
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
  (@obligationId, @authorId, 'Obligation', 'Obligation request', 0),
  (@answeredId, @authorId, 'Answered', 'Answered forward', 0),
  (@deletedId, @authorId, 'Deleted', 'Deleted request', 2)
'''),
    parameters: {
      'ownedId': _ownedBeaconId,
      'forwardedId': _forwardedBeaconId,
      'obligationId': _obligationBeaconId,
      'answeredId': _answeredBeaconId,
      'deletedId': _deletedBeaconId,
      'viewerId': _viewerId,
      'authorId': _authorId,
    },
  );
  for (final entry in const [
    ('Fu10aunif01', _forwardedBeaconId),
    ('Fu10aunif02', _obligationBeaconId),
    ('Fu10aunif03', _answeredBeaconId),
    ('Fu10aunif04', _deletedBeaconId),
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
  // Addition 3 (U10a remediation). The committed fixture inserted no
  // `inbox_item` explicitly and no tombstone `access_policy` at all. The
  // pinned zone was in fact *not* empty — `inbox_item_on_forward_insert`
  // (m0014) materialises a row for every `beacon_forward_edge` — but nothing
  // said so, and the edge rows that matter most were missing. Every
  // `inbox_item` below is written as an upsert over that trigger's row, one
  // per clause of `eligible_pinned`, so each exclusion carries a witness and
  // a widening in U10b/U10c cannot hide in an unexamined set.

  // A tombstone the viewer may read only as a tombstone: the Request is
  // deleted, so `beacon_can_read_content` is false while
  // `beacon_can_read_tombstone` is true. Restricted `access_policy`.
  await _insertReceipt(
    writer,
    id: 'Nu10auniftmb',
    beaconId: _deletedBeaconId,
    accessPolicy: 'beacon_tombstone',
  );
  // CHANGES IN U15R-e: the Request-less obligation fixture is gone. m0191
  // (`notification_outbox__obligation_beacon_chk`) makes the shape unstorable
  // — the producer already refused to emit it, and now the database does too
  // — so this INSERT fails at setUpAll rather than reaching `visible`. The
  // `beacon_id IS NOT NULL` clause in the `scope` CTE it used to isolate is
  // consequently unreachable for any storable row; it stays in the SQL
  // because `scope` is authorization-critical and should not depend on a
  // constraint added elsewhere, and the constraint itself is pinned by name
  // in attention_active_attention_axis_pg_test.dart.

  // Unanswered forward: readable, status 0, outside scope. The single row
  // `eligible_pinned` must contain, and the one the sweep must never touch.
  await _insertInboxItem(writer, beaconId: _forwardedBeaconId);
  // Excluded by the scope clause: same shape, but a live obligation on the
  // Request pulls it into My Desk.
  await _insertInboxItem(writer, beaconId: _obligationBeaconId);
  // Excluded by the readability clause: content unreadable on a deleted
  // Request, even though the row itself is status 0 and undismissed.
  await _insertInboxItem(writer, beaconId: _deletedBeaconId);
  // Excluded by status and by `tombstone_dismissed_at`: an answered forward
  // whose outcome is a dismissible tombstone, already dismissed.
  await _insertDismissedTombstone(writer, beaconId: _answeredBeaconId);
}

Future<void> _insertInboxItem(
  Connection writer, {
  required String beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@userId, @beaconId, 0, 1, now(), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE
  SET status = 0, tombstone_dismissed_at = NULL
'''),
  parameters: {'userId': _viewerId, 'beaconId': beaconId},
);

/// Tombstone statuses may only be written with the beacon trigger's flag, so
/// this borrows it for exactly one statement inside one transaction.
Future<void> _insertDismissedTombstone(
  Connection writer, {
  required String beaconId,
}) => writer.runTx((tx) async {
  await tx.execute(
    "SELECT set_config('tentura.allow_inbox_tombstone_transition', '1', true)",
  );
  await tx.execute('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message, tombstone_dismissed_at
) VALUES ('$_viewerId', '$beaconId', 4, 1, now(), '', '', now())
ON CONFLICT (user_id, beacon_id) DO UPDATE
  SET status = 4, tombstone_dismissed_at = now()
''');
});

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String? beaconId,
  bool requiresAction = false,
  String? accessPolicy,
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
    'accessPolicy':
        accessPolicy ?? (beaconId == null ? 'profile' : 'beacon_content'),
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
  },
);
