@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/data/repository/author_invite_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/use_case/attention_sweep_case.dart';

import '../../support/disposable_pg_target.dart';

/// The Activity feed, *Dismiss all* and undo answer one question about an
/// inbox outcome row: may the viewer still read this Request (or read it as a
/// tombstone)? They must answer it the same way.
///
/// Four rows, one per answer the guard can give:
///
/// * readable — a live forward to the viewer;
/// * blocked author — either the author or the viewer initiates the block;
/// * unreadable — the forward that gave the viewer access is gone;
/// * tombstone only — the Request was deleted, the viewer may read only its
///   tombstone (the second branch of the guard).
///
/// Before a sweep: the feed shows an outcome iff *Dismiss all* hides it.
/// After a sweep and a change of access: every captured outcome is classified,
/// not just the changed row. An independent replay of the same access state
/// with undismissed fixtures checks what the feed and Dismiss all would accept;
/// otherwise a lingering dismissal could mask an incorrect readability guard.
///
/// Coverage: shared predicate shape/composition is in the sibling guard test;
/// this real PostgreSQL path covers feed, Dismiss all and undo agreement.
/// Siblings: surface = Activity feed / sweep / undo; role = forwarded viewer
/// and blocked viewer; state = live and deleted Request; freshness = access
/// retained/lost after sweep. Input, network, width and locale are n/a because
/// this server SQL refactor changes no UI or transport behavior. Posts are
/// n/a because these outcome rows are Request-only. No MeritRank code changes.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_OUTCOME_READABILITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_outcome_readability',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late AttentionRepository feed;
  late AttentionSweepCase sweep;

  setUpAll(() async {
    if (skipReason != false) return;
    // The Activity feed's grouped provenance ranks through pgmer2.
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    writer = session.writer;
    database = openDisposablePgDatabase(target);
    feed = AttentionRepository(database);
    sweep = AttentionSweepCase(AttentionSweepRepository(database));
  });

  tearDownAll(() async {
    if (skipReason != false) return;
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    if (skipReason != false) return;
    await _resetFixtures(writer);
  });

  /// The Requests whose outcome row is on the viewer's Activity feed.
  Future<Set<String>> feedOutcomes() async {
    final page = await feed.attentionFeed(
      accountId: _viewerId,
      view: AttentionFeedView.all,
      surface: AttentionSurface.activity,
    );
    return {
      for (final item in page.page.items)
        if (item.itemKind == AttentionItemKind.forward &&
            item.id.startsWith('inbox:'))
          item.id.substring('inbox:'.length),
    };
  }

  test(
    'pending invites require content access even when tombstones are readable',
    () async {
      await _blockAuthor(writer);
      await _dropForward(writer, _unreadableBeaconId);
      for (final beaconId in _allBeaconIds) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_author_invite
  (id, beacon_id, inviter_id, invitee_id, warm)
SELECT @id, id, user_id, @viewer, false
FROM public.beacon WHERE id = @beacon
'''),
          parameters: {
            'id': 'BI$beaconId',
            'viewer': _viewerId,
            'beacon': beaconId,
          },
        );
      }

      final pending = await AuthorInviteRepository(
        database,
      ).listPendingForInvitee(_viewerId);
      expect(pending.map((invite) => invite.beaconId).toSet(), {
        _readableBeaconId,
      });
      expect(await feedOutcomes(), {_readableBeaconId, _tombstoneBeaconId});
    },
    skip: skipReason,
  );

  group('feed and Dismiss all agree before a sweep', () {
    test('the feed shows exactly the outcomes Dismiss all hides', () async {
      await _blockAuthor(writer);
      await _dropForward(writer, _unreadableBeaconId);

      final shown = await feedOutcomes();
      final swept = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPreadagree1',
      );

      expect(shown, {_readableBeaconId, _tombstoneBeaconId});
      expect(swept.appliedOutcomeBeaconIds.toSet(), shown);
    });
  }, skip: skipReason);

  group('feed, Dismiss all and undo agree after access changes', () {
    for (final scenario in _accessChanges) {
      test(
        '${scenario.name}: every outcome has the same visibility classification',
        () async {
          final readable = _allBeaconIds.difference(scenario.unreadable);
          expect(await feedOutcomes(), _allBeaconIds);
          final swept = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPreadundo',
          );
          expect(
            swept.appliedOutcomeBeaconIds.toSet(),
            _allBeaconIds,
            reason: 'every outcome is readable, and so swept, at sweep time',
          );
          expect(
            await feedOutcomes(),
            isEmpty,
            reason: 'a swept outcome is off the feed until undo',
          );

          await scenario.changeAccess(writer);

          final undone = await sweep.undo(
            accountId: _viewerId,
            operationId: swept.operationId,
            undoToken: swept.undoToken!,
          );
          final shown = await feedOutcomes();

          expect(undone.refusal, isNull);
          expect(undone.failed, isEmpty);
          expect(undone.restoredReceiptIds, isEmpty);
          expect(undone.restoredOutcomeBeaconIds.toSet(), readable);
          expect(undone.restoredOutcomeBeaconIds, hasLength(readable.length));
          expect(shown, readable);
          expect(
            undone.restoredOutcomeBeaconIds.toSet(),
            shown,
            reason: 'what undo puts back is exactly what the feed shows',
          );
          expect(undone.skipped, hasLength(scenario.unreadable.length));
          final refused = {
            for (final member in undone.skipped)
              if (member.kind == 'outcome' &&
                  member.reason == AttentionUndoSkipReason.notAuthorized)
                member.id,
          };
          expect(
            refused,
            scenario.unreadable,
            reason: 'an outcome the feed hides is refused as not authorized',
          );

          // Replay the changed access state with undismissed outcomes. This
          // independently checks readability for the rows undo refused, whose
          // dismissal markers would otherwise hide them regardless of access.
          await _resetFixtures(writer);
          await scenario.changeAccess(writer);
          final shownWithChangedAccess = await feedOutcomes();
          expect(shownWithChangedAccess, readable);
          final sweptWithChangedAccess = await sweep.dismissAll(
            accountId: _viewerId,
            operationId: 'OPchangedaccess',
          );
          expect(
            sweptWithChangedAccess.appliedOutcomeBeaconIds.toSet(),
            readable,
          );
          expect(
            sweptWithChangedAccess.appliedOutcomeBeaconIds.toSet(),
            undone.restoredOutcomeBeaconIds.toSet(),
            reason:
                'Dismiss all and undo must accept exactly the same rows '
                'at the same access state',
          );
          expect(await feedOutcomes(), isEmpty);
        },
      );
    }
  }, skip: skipReason);
}

typedef _AccessChange = ({
  String name,
  Set<String> unreadable,
  Future<void> Function(Connection writer) changeAccess,
});

final List<_AccessChange> _accessChanges = [
  (
    name: 'live and tombstone access retained',
    unreadable: {},
    changeAccess: (_) async {},
  ),
  (
    name: 'live Request author blocks the viewer',
    unreadable: {_blockedBeaconId},
    changeAccess: _blockAuthor,
  ),
  (
    name: 'viewer blocks the live Request author',
    unreadable: {_blockedBeaconId},
    changeAccess: _viewerBlocksAuthor,
  ),
  (
    name: 'live Request loses its access-granting forward',
    unreadable: {_unreadableBeaconId},
    changeAccess: (writer) => _dropForward(writer, _unreadableBeaconId),
  ),
  (
    name: 'deleted Request retains tombstone access without its forward',
    unreadable: {},
    changeAccess: (writer) => _dropForward(writer, _tombstoneBeaconId),
  ),
  (
    name: 'deleted Request retains tombstone access despite an author block',
    unreadable: {_readableBeaconId, _unreadableBeaconId},
    // Tombstone access comes from the inbox row itself and ignores blocks.
    // The same author's live Requests must still become unreadable.
    changeAccess: (writer) => _blockAuthor(writer, authorId: _authorId),
  ),
  (
    name: 'purged Request loses tombstone access',
    unreadable: {_tombstoneBeaconId},
    changeAccess: _purgeTombstone,
  ),
  (
    name: 'blocked, unforwarded and purged Requests beside a readable outcome',
    unreadable: {
      _blockedBeaconId,
      _unreadableBeaconId,
      _tombstoneBeaconId,
    },
    changeAccess: (writer) async {
      await _blockAuthor(writer);
      await _dropForward(writer, _unreadableBeaconId);
      await _purgeTombstone(writer);
    },
  ),
];

const _allBeaconIds = {
  _readableBeaconId,
  _blockedBeaconId,
  _unreadableBeaconId,
  _tombstoneBeaconId,
};

const _viewerId = 'Ureadguard01';
const _authorId = 'Ureadguard02';
const _blockedAuthorId = 'Ureadguard03';
const _readableBeaconId = 'Breadguardok';
const _blockedBeaconId = 'Breadguardblk';
const _unreadableBeaconId = 'Breadguardgone';
const _tombstoneBeaconId = 'Breadguardtmb';

Future<void> _blockAuthor(
  Connection writer, {
  String authorId = _blockedAuthorId,
}) => writer.execute(
  Sql.named(
    'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
    'VALUES (@blocker, @blocked, @blocked)',
  ),
  parameters: {'blocker': authorId, 'blocked': _viewerId},
);

Future<void> _purgeTombstone(Connection writer) => writer.execute(
  Sql.named('DELETE FROM public.beacon WHERE id = @id'),
  parameters: {'id': _tombstoneBeaconId},
);

Future<void> _viewerBlocksAuthor(Connection writer) => writer.execute(
  Sql.named(
    'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
    'VALUES (@blocker, @blocked, @blocked)',
  ),
  parameters: {'blocker': _viewerId, 'blocked': _blockedAuthorId},
);

/// Removes the forward that gave the viewer read access to the Request.
Future<void> _dropForward(Connection writer, String beaconId) => writer.execute(
  Sql.named(
    'DELETE FROM public.beacon_forward_edge WHERE beacon_id = @id',
  ),
  parameters: {'id': beaconId},
);

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.beacon_help_offer,
  public.inbox_item,
  public.beacon_forward_edge,
  public.attention_clear_operation,
  public.attention_request_state,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_viewerId, _authorId, _blockedAuthorId]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': '$id-key'},
    );
  }
  for (final (beaconId, authorId, beaconStatus) in [
    (_readableBeaconId, _authorId, 0),
    (_blockedBeaconId, _blockedAuthorId, 0),
    (_unreadableBeaconId, _authorId, 0),
    (_tombstoneBeaconId, _authorId, 2),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Forwarded', 'Forwarded request', @status)
'''),
      parameters: {
        'id': beaconId,
        'authorId': authorId,
        'status': beaconStatus,
      },
    );
    // Forwarding creates the viewer's inbox row
    // (`inbox_item_on_forward_insert`).
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES (@id, @beaconId, @senderId, @recipientId)
'''),
      parameters: {
        'id': 'FE$beaconId',
        'beaconId': beaconId,
        'senderId': authorId,
        'recipientId': _viewerId,
      },
    );
  }
  // Answered outcomes: «Not interested» on the live Requests, «Watching» on
  // the one about to become a tombstone.
  for (final (beaconId, status) in [
    (_readableBeaconId, 2),
    (_blockedBeaconId, 2),
    (_unreadableBeaconId, 2),
    (_tombstoneBeaconId, 1),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (@userId, @beaconId, @status, 1, now(), '', '')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
      parameters: {'userId': _viewerId, 'beaconId': beaconId, 'status': status},
    );
  }
  // The deleted Request's row becomes «deleted before you answered».
  await writer.execute(
    Sql.named(
      'SELECT public.inbox_item_apply_tombstone_after_withdraw(@userId, '
      '@beaconId)',
    ),
    parameters: {'userId': _viewerId, 'beaconId': _tombstoneBeaconId},
  );
}
