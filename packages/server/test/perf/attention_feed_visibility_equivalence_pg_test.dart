@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../support/disposable_pg_target.dart';
import '../support/pg_test_public_keys.dart';
import 'attention_feed_pre_fix_sql.dart';
import 'attention_feed_statement_rows.dart';

/// The AttentionFeed visibility rewrite must be a pure speed change: for every
/// kind of viewer, each statement built on `visible_attention_receipts`
/// returns exactly what the pre-fix SQL returned on the same data.
///
/// The reference half runs the frozen pre-fix statements
/// (`attention_feed_pre_fix_sql.dart`) on the schema as it stood before the
/// fix. The database is then migrated to head and the same viewers are read
/// through the real [AttentionRepository]. Viewers cover each visibility
/// branch: the Request's author, a helper it was forwarded to, an unrelated
/// person, and a person the author blocked after forwarding to them.
///
/// Dropping the visibility filter from the head SQL fails these tests: the
/// unrelated and blocked viewers would then see the author's Requests.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_FEED_EQUIVALENCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_feed_equiv',
  );
  final skipReason = await pgSkipReason(target);

  group(
    'visible attention statements return the pre-fix results for every '
    'kind of viewer',
    skip: skipReason,
    () {
      late DisposablePgWriterSession session;
      TenturaDb? database;
      late StatementRowCapture after;
      late AttentionRepository repository;
      final reference = <String, _ViewerResult>{};

      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
          lastInclusiveVersion: preFixSchemaVersion,
        );
        await _seed(session.writer);

        // Reference: the frozen pre-fix SQL on the pre-fix schema.
        final before = TenturaDb(target.databaseEnv);
        try {
          for (final viewer in _viewers.keys) {
            reference[viewer] = await _readReference(before, viewer);
          }
        } finally {
          await before.close();
        }

        // Candidate: head schema, read through the real repository.
        await migrateDbSchema(session.writer);
        after = StatementRowCapture();
        database = TenturaDb(
          target.databaseEnv,
          scopeInterceptor: () => after,
        );
        repository = AttentionRepository(database!);
      });

      tearDownAll(
        () => tearDownDisposablePgWriter(session: session, drift: database),
      );

      test('the pre-fix reference itself tells the four viewers apart', () {
        _expectReferenceTellsViewersApart(reference);
      });

      for (final surface in [null, AttentionSurface.activity]) {
        final name = surface?.name ?? 'history';
        test(
          'the $name feed statement returns the pre-fix rows in the pre-fix '
          'order for the author, the forwarded helper, the unrelated and the '
          'blocked viewer',
          () async {
            for (final MapEntry(key: viewer, value: role) in _viewers.entries) {
              after.clear();
              await repository.attentionFeed(
                accountId: viewer,
                view: AttentionFeedView.all,
                surface: surface,
              );
              final expected = reference[viewer]!;
              expectSameFeedRows(
                actual: after.feedStatementRows(),
                expected: surface == null
                    ? expected.history
                    : expected.activity,
                reason:
                    '$role ($viewer), $name feed: the statement must return '
                    'the pre-fix rows in the pre-fix order.',
              );
            }
          },
        );
      }

      // DISTINCT with no ORDER BY: the statement defines no order, and the
      // repository returns a set, so the comparison is on the set.
      test(
        'live obligations name the pre-fix Requests for the author, the '
        'forwarded helper, the unrelated and the blocked viewer',
        () async {
          for (final MapEntry(key: viewer, value: role) in _viewers.entries) {
            expect(
              await repository.liveObligationBeacons(accountId: viewer),
              reference[viewer]!.live,
              reason: '$role ($viewer): live obligations changed.',
            );
          }
        },
      );

      test(
        'unread Requests name the pre-fix Requests for the author, the '
        'forwarded helper, the unrelated and the blocked viewer',
        () async {
          for (final MapEntry(key: viewer, value: role) in _viewers.entries) {
            expect(
              await repository.unreadForBeacons(
                accountId: viewer,
                beaconIds: _requestIds.toSet(),
              ),
              reference[viewer]!.unread,
              reason: '$role ($viewer): unread Requests changed.',
            );
          }
        },
      );
    },
  );
}

typedef _ViewerResult = ({
  List<Map<String, Object?>> history,
  List<Map<String, Object?>> activity,
  Set<String> live,
  Set<String> unread,
});

const _authorId = 'Ufeedeqv01';
const _helperId = 'Ufeedeqv02';
const _unrelatedId = 'Ufeedeqv03';
const _blockedId = 'Ufeedeqv04';
const _openRequestId = 'Bfeedeqv01';
const _cancelledForwardRequestId = 'Bfeedeqv02';
const _deletedRequestId = 'Bfeedeqv03';

const _viewers = {
  _authorId: 'author',
  _helperId: 'forwarded helper',
  _unrelatedId: 'unrelated user',
  _blockedId: 'blocked user',
};

const _requestIds = [
  _openRequestId,
  _cancelledForwardRequestId,
  _deletedRequestId,
];

Future<_ViewerResult> _readReference(TenturaDb database, String viewer) async {
  Future<List<Map<String, Object?>>> rows(
    String sql,
    List<Variable> variables,
  ) async => [
    for (final row
        in await database.customSelect(sql, variables: variables).get())
      row.data,
  ];
  List<Variable> feed(String? surface) => [
    Variable<String>(viewer),
    const Variable<String>('all'),
    const Variable<String>(null),
    Variable<String>(surface),
    const Variable<int>(51),
  ];
  Set<String> beaconIds(List<Map<String, Object?>> rows) => {
    for (final row in rows) row['beacon_id']! as String,
  };
  return (
    history: await rows(preFixAttentionFeedHistorySql, feed(null)),
    activity: await rows(preFixAttentionFeedActivitySql, feed('activity')),
    live: beaconIds(
      await rows(preFixLiveObligationBeaconsSql, [Variable<String>(viewer)]),
    ),
    unread: beaconIds(
      await rows(preFixUnreadForThreeBeaconsSql, [
        Variable<String>(viewer),
        for (final id in _requestIds) Variable<String>(id),
      ]),
    ),
  );
}

/// The reference itself must distinguish the viewers, otherwise "identical
/// results" would also hold for SQL that ignores visibility.
void _expectReferenceTellsViewersApart(Map<String, _ViewerResult> reference) {
  List<Map<String, Object?>> rowsOn(String viewer, String beacon) => [
    for (final row in reference[viewer]!.history)
      if (row['beacon_id'] == beacon) row,
  ];
  List<Object?> pageIds(String viewer) => [
    for (final row in reference[viewer]!.history) row['id'],
  ];

  for (final viewer in [_authorId, _helperId]) {
    final role = _viewers[viewer];
    expect(
      rowsOn(viewer, _openRequestId),
      isNotEmpty,
      reason: 'The $role reads the open Request.',
    );
    expect(reference[viewer]!.live, {_openRequestId}, reason: role);
    expect(reference[viewer]!.unread, contains(_openRequestId), reason: role);
  }
  for (final viewer in [_unrelatedId, _blockedId]) {
    final role = _viewers[viewer];
    expect(
      pageIds(viewer),
      isNot(equals(pageIds(_authorId))),
      reason: 'The $role must not see what the author sees.',
    );
    expect(
      rowsOn(viewer, _openRequestId),
      isEmpty,
      reason: 'The $role has receipts on the open Request but cannot read it.',
    );
    expect(reference[viewer]!.live, isEmpty, reason: role);
    expect(reference[viewer]!.unread, isEmpty, reason: role);
  }
  expect(
    rowsOn(_authorId, _cancelledForwardRequestId),
    isNotEmpty,
    reason: 'The author still reads a Request whose forward was withdrawn.',
  );
  expect(
    rowsOn(_helperId, _cancelledForwardRequestId),
    isEmpty,
    reason: 'A withdrawn forward no longer lets the helper read the Request.',
  );
  expect(
    [
      for (final row in rowsOn(_helperId, _deletedRequestId))
        (row['access_policy'], row['tombstone_copy']),
    ],
    [('beacon_tombstone', true)],
    reason:
        'The helper sees a deleted Request only through its tombstone '
        'receipt, as a tombstone copy; its content receipt stays hidden.',
  );
  expect(
    rowsOn(_unrelatedId, _deletedRequestId),
    isEmpty,
    reason: 'An unrelated person gets no tombstone of a deleted Request.',
  );
}

Future<void> _seed(Connection writer) async {
  for (final (slot, id) in _viewers.keys.indexed) {
    await writer.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @id, @key)',
      ),
      parameters: {'id': id, 'key': pgTestPublicKey('feedequiv', slot + 1)},
    );
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@open, @author, 'Open request', 'Equivalence fixture', 0),
  (@cancelled, @author, 'Forward withdrawn', 'Equivalence fixture', 0),
  (@deleted, @author, 'Deleted request', 'Equivalence fixture', 0)
'''),
    parameters: {
      'open': _openRequestId,
      'cancelled': _cancelledForwardRequestId,
      'deleted': _deletedRequestId,
      'author': _authorId,
    },
  );
  for (final (beacon, recipient, cancelled) in [
    (_openRequestId, _helperId, false),
    (_openRequestId, _blockedId, false),
    (_cancelledForwardRequestId, _helperId, true),
    (_deletedRequestId, _helperId, false),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, note, created_at, cancelled_at
) VALUES (
  @id, @beacon, @author, @recipient, 'fixture', now(),
  CASE WHEN @cancelled THEN now() END
)
'''),
      parameters: {
        'id': 'FEfeedeqv$beacon$recipient',
        'beacon': beacon,
        'author': _authorId,
        'recipient': recipient,
        'cancelled': cancelled,
      },
    );
  }
  await writer.execute(
    Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
    parameters: {'id': _deletedRequestId},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
      'VALUES (@author, @blocked, @blocked)',
    ),
    parameters: {'author': _authorId, 'blocked': _blockedId},
  );

  // Every viewer gets the same receipt mix; visibility alone tells them apart.
  for (final viewer in _viewers.keys) {
    final receipts = [
      (beacon: _openRequestId, policy: 'beacon_content', action: false),
      (beacon: _openRequestId, policy: 'beacon_content', action: true),
      (
        beacon: _cancelledForwardRequestId,
        policy: 'beacon_content',
        action: false,
      ),
      (beacon: _deletedRequestId, policy: 'beacon_tombstone', action: false),
      (beacon: _deletedRequestId, policy: 'beacon_content', action: false),
      (beacon: null, policy: 'profile', action: false),
    ];
    for (final (n, receipt) in receipts.indexed) {
      final profile = receipt.policy == 'profile';
      await writer.execute(
        Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, attention_thread_key, created_at
) VALUES (
  @id, @viewer, 'coordination', 'coordinationChanged', 'normal',
  'Fixture receipt', 'Equivalence fixture', '/attention',
  @id, @beacon, @id, @destination, @presentation, '{}'::jsonb, 'standard',
  @policy, @action, @thread,
  '2026-11-01T00:00:00Z'::timestamptz + @n * interval '1 minute'
)
'''),
        parameters: {
          'id': 'Nfeedeqv$viewer$n',
          'viewer': viewer,
          'beacon': receipt.beacon,
          'destination': profile ? 'profile' : 'beacon',
          'presentation': profile
              ? 'invite_accepted'
              : 'request_status_changed',
          'policy': receipt.policy,
          'action': receipt.action,
          'thread': receipt.action
              ? 'v1|request|${receipt.beacon}|$viewer'
              : null,
          'n': n,
        },
      );
    }
  }
}
