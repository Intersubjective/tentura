@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';

/// U09a step 3 — `attention_request_state` acquires its first writer.
///
/// The counters exist so undo can refuse to re-hide something the viewer has
/// since restored or re-pinned. Every case below is therefore phrased as the
/// question undo will ask: *has this outcome, or this decision, moved since I
/// captured it?*
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U09A_STATE_TEST_DB',
    defaultNamePrefix: 'tentura_test_u09a_state',
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
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  test('an inbox row lazily creates the Request state', () async {
    await _forward(writer);

    final state = await _state(writer);
    expect(state, isNotNull);
    expect(state!.outcomeGeneration, 0);
    expect(state.decisionRevision, 0);
    expect(
      state.firstEntryAt,
      isNotNull,
      reason: 'the stable ordering anchor D08 needs is populated on entry',
    );
  }, skip: skipReason);

  test('a stance change is both a new decision and a new outcome', () async {
    await _forward(writer);

    await writer.execute(
      "UPDATE public.inbox_item SET status = 2, rejection_message = 'no thanks' "
      "WHERE user_id = '$_viewerId'",
    );

    final state = (await _state(writer))!;
    expect(state.decisionRevision, 1);
    expect(state.outcomeGeneration, 1);
  }, skip: skipReason);

  test('Restore is a decision too — undo must see it', () async {
    // Restore is the motivating case: the client performs it through Hasura,
    // so a Dart-level writer would never have noticed it.
    await _forward(writer);
    await writer.execute(
      "UPDATE public.inbox_item SET status = 2 WHERE user_id = '$_viewerId'",
    );
    await writer.execute(
      "UPDATE public.inbox_item SET status = 0 WHERE user_id = '$_viewerId'",
    );

    final state = (await _state(writer))!;
    expect(state.decisionRevision, 2);
    expect(state.outcomeGeneration, 2);
  }, skip: skipReason);

  test(
    'a new forward generation replaces the outcome without deciding anything',
    () async {
      await _forward(writer);

      await writer.execute(
        'UPDATE public.inbox_item '
        "SET latest_forward_at = now(), forward_count = forward_count + 1 "
        "WHERE user_id = '$_viewerId'",
      );

      final state = (await _state(writer))!;
      expect(state.outcomeGeneration, 1);
      expect(
        state.decisionRevision,
        0,
        reason: 'somebody forwarded again; the viewer decided nothing',
      );
    },
    skip: skipReason,
  );

  test('a terminal state reached through the beacon trigger counts', () async {
    // The beacon trigger writes `inbox_item` in SQL, with no Dart involved at
    // all — the second reason this writer is a trigger.
    await _forward(writer);

    await writer.execute(
      "UPDATE public.beacon SET status = 2 WHERE id = '$_beaconId'",
    );

    final status = await writer.execute(
      "SELECT status FROM public.inbox_item WHERE user_id = '$_viewerId'",
    );
    expect(status.first.first, 4);

    final state = (await _state(writer))!;
    expect(state.outcomeGeneration, greaterThanOrEqualTo(1));
    expect(state.decisionRevision, 1);
  }, skip: skipReason);

  test('dismissing an outcome does not invalidate its own undo', () async {
    await _forward(writer);
    await writer.execute(
      "UPDATE public.inbox_item SET status = 1 WHERE user_id = '$_viewerId'",
    );
    final before = (await _state(writer))!;

    await writer.execute(
      'UPDATE public.inbox_item SET tombstone_dismissed_at = now() '
      "WHERE user_id = '$_viewerId'",
    );
    final afterDismiss = (await _state(writer))!;

    await writer.execute(
      'UPDATE public.inbox_item SET tombstone_dismissed_at = NULL '
      "WHERE user_id = '$_viewerId'",
    );
    final afterUndo = (await _state(writer))!;

    for (final state in [afterDismiss, afterUndo]) {
      expect(
        state.outcomeGeneration,
        before.outcomeGeneration,
        reason:
            'a sweep that bumped the generation would refuse to undo itself',
      );
      expect(state.decisionRevision, before.decisionRevision);
    }
  }, skip: skipReason);

  test('each viewer keeps their own state', () async {
    await _forward(writer);
    await _forward(writer, recipientId: _otherViewerId, edgeId: 'Fu09ast02');

    await writer.execute(
      "UPDATE public.inbox_item SET status = 1 WHERE user_id = '$_viewerId'",
    );

    expect((await _state(writer))!.decisionRevision, 1);
    expect(
      (await _state(writer, accountId: _otherViewerId))!.decisionRevision,
      0,
      reason: 'never reverses another person\'s action (D13)',
    );
  }, skip: skipReason);
}

const _viewerId = 'Uu09ast01';
const _otherViewerId = 'Uu09ast02';
const _authorId = 'Uu09ast03';
const _beaconId = 'Bu09ast01';

typedef _RequestState = ({
  int outcomeGeneration,
  int decisionRevision,
  DateTime? firstEntryAt,
});

Future<_RequestState?> _state(
  Connection writer, {
  String accountId = _viewerId,
}) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT outcome_generation, decision_revision, first_entry_at
  FROM public.attention_request_state
 WHERE account_id = @accountId AND beacon_id = @beaconId
'''),
    parameters: {'accountId': accountId, 'beaconId': _beaconId},
  );
  if (rows.isEmpty) return null;
  return (
    outcomeGeneration: rows.first[0]! as int,
    decisionRevision: rows.first[1]! as int,
    firstEntryAt: rows.first[2] as DateTime?,
  );
}

/// The inbox row is created by `inbox_item_on_forward_insert`, as in life.
Future<void> _forward(
  Connection writer, {
  String recipientId = _viewerId,
  String edgeId = 'Fu09ast01',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
  parameters: {
    'id': edgeId,
    'beaconId': _beaconId,
    'senderId': _authorId,
    'recipientId': recipientId,
  },
);

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _otherViewerId, _authorId]) {
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
VALUES (@beaconId, @authorId, 'State', 'State request', 0)
'''),
    parameters: {'beaconId': _beaconId, 'authorId': _authorId},
  );
}
