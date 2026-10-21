@Tags(['pg', 'mr', 'repo-files'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// `my desk.dot` (docs/features/request-attention.md §6): "any owned Request
/// has a dot", where `request.dot` counts an uncleared *outcome* as well as an
/// uncleared optional event.
///
/// An outcome row is a memory of the viewer's own answer to a forward. The
/// author of a Request is never the recipient of a forward of it, so an own
/// Request has no outcome row at all (#412) — the only Requests that can carry
/// an outcome into the responsibility scope are ones the viewer is helping.
/// These cases pin the outcome leg of the dot on that population.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MY_DESK_DOT_OUTCOME_TEST_DB',
    defaultNamePrefix: 'tentura_test_desk_dot_outcome',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('my desk.dot — outcome leg', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.attention_clear_operation,
  public.beacon_help_offer,
  public.beacon_archived,
  public.beacon_forward_edge,
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
  (@helpedId, @authorId, 'Helped', 'Helped request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'helpedId': _helpedBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('an uncleared outcome on a Request I am helping lights my desk.dot',
        () async {
      await _forwardEdge(writer, id: 'FEdh01', beaconId: _helpedBeaconId);
      await _offerHelp(writer, beaconId: _helpedBeaconId);

      final summary = await query.surfaceSummary(accountId: _viewerId);

      expect(
        summary.myDeskDot,
        isTrue,
        reason: 'the Request is in my responsibility scope and its outcome '
            '("You\'re helping") is uncleared (§6 request.dot)',
      );
    });

    test('a cleared outcome on a Request I am helping no longer lights my '
        'desk.dot', () async {
      await _forwardEdge(writer, id: 'FEdh02', beaconId: _helpedBeaconId);
      await _offerHelp(writer, beaconId: _helpedBeaconId);
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).myDeskDot,
        isTrue,
        reason: 'precondition: the outcome is uncleared and lights the dot',
      );

      // Clearing an outcome is dismissing its row (the × / Dismiss all).
      final cleared = await writer.execute(
        Sql.named('''
UPDATE public.inbox_item
SET tombstone_dismissed_at = now()
WHERE user_id = @u AND beacon_id = @b
'''),
        parameters: {'u': _viewerId, 'b': _helpedBeaconId},
      );
      expect(cleared.affectedRows, 1);

      expect(
        (await query.surfaceSummary(accountId: _viewerId)).myDeskDot,
        isFalse,
        reason: '§6 request.dot is about *uncleared* outcomes: reading or '
            'having had one is not enough once it is cleared',
      );
    });

    test('an owned Request with a forward edge to its author has no outcome '
        'row, so it does not light my desk.dot', () async {
      // The state a stale expectation used to call "an uncleared outcome on
      // an owned Request": a forward edge materialises an `inbox_item` for
      // the author on their own Request.
      await _forwardEdge(writer, id: 'FEdo01', beaconId: _ownedBeaconId);

      // Precondition: the inbox row really exists, so everything below is the
      // projection's decision and not a fixture gap.
      final inbox = await writer.execute(
        Sql.named('''
SELECT status FROM public.inbox_item
WHERE user_id = @u AND beacon_id = @b AND tombstone_dismissed_at IS NULL
'''),
        parameters: {'u': _viewerId, 'b': _ownedBeaconId},
      );
      expect(inbox, hasLength(1));

      final summary = await query.surfaceSummary(accountId: _viewerId);
      final myDesk = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.myWork,
      );
      final activity = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );

      expect(
        activity.page.items.where((item) => item.beaconId == _ownedBeaconId),
        isEmpty,
        reason: 'an author is never their own forward recipient (#412), so '
            'an own Request has no outcome row to be uncleared',
      );
      expect(
        summary.myDeskDot,
        isFalse,
        reason: 'no uncleared optional event and no outcome: nothing to light '
            '(§6 request.dot)',
      );
      expect(
        myDesk.page.items.where((item) => item.beaconId == _ownedBeaconId),
        isEmpty,
        reason: 'the dot and the My desk default list are one predicate (M1)',
      );
      expect(summary.forYouDot, isFalse);
      expect(summary.forYouSweepEligible, isFalse);
    });
  }, skip: skipReason);
}

Future<void> _forwardEdge(
  Connection writer, {
  required String id,
  required String beaconId,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (@id, @beaconId, @authorId, @viewerId,
  CAST('2026-08-10T10:00:00Z' AS timestamptz), NULL)
'''),
  parameters: {
    'id': id,
    'beaconId': beaconId,
    'authorId': _authorId,
    'viewerId': _viewerId,
  },
);

Future<void> _offerHelp(Connection writer, {required String beaconId}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@beaconId, @userId, 'offer', 0, now(), now())
'''),
      parameters: {'beaconId': beaconId, 'userId': _viewerId},
    );

const _viewerId = 'Udesk01';
const _authorId = 'Udesk02';
const _ownedBeaconId = 'Bdeskowned';
const _helpedBeaconId = 'Bdeskhelped';
