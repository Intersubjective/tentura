@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../support/attention_case_factory.dart';
import '../../domain/attention/attention_case_test_support.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/production_receipt_transport.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

// «Read all» in History must clear unread dots only: the viewer's Activity
// keeps its outcome (tombstone) row and its pending forwarded Request. Real
// path: production GraphQL server on Postgres -> Ferry -> repository -> case
// -> cubits. A reload is a new case and cubits over the same server state.
const _viewer = 'Ua00000000005';
const _tombstoneBeaconId = 'Bfwdtomb00001';
const _tombstoneRowId = 'inbox:$_tombstoneBeaconId';
const _pendingBeaconId = 'Bfwdreq000001';

Future<void> _until(bool Function() ready, {Object? Function()? why}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out: ${why?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// History and Activity cubits over one [AttentionCase], like an open app.
final class _Session {
  _Session._(
    this.remote,
    this.accounts,
    this.sync,
    this.attention,
    this.repository,
    this.history,
    this.activity,
  );

  final RemoteApiService remote;
  final AttentionCaseTestAccounts accounts;
  final ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  final AttentionCase attention;
  final AttentionRepository repository;
  final UpdatesFeedCubit history;
  final UpdatesFeedCubit activity;

  static Future<_Session> open() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    await remote.setSessionAuth();
    final accounts = AttentionCaseTestAccounts();
    final sync = buildTestRealtimeSync();
    final repository = AttentionRepository(remote);
    final attention = buildAttentionCase(
      repository: repository,
      accounts: accounts,
      realtimeSyncCase: sync.case_,
      blockCase: noopBlockCase(),
      feedSessions: FeedSessionRegistry(),
      logger: Logger('history-read-all-activity'),
    );
    accounts.emit(_viewer);
    await Future<void>.delayed(Duration.zero);
    UpdatesFeedCubit cubit(String destination) => UpdatesFeedCubit(
      destinationId: destination,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('history-read-all-activity-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    final history = cubit(AttentionFeedDestinationId.history);
    final activity = cubit(AttentionFeedDestinationId.activityStream);
    try {
      await _until(
        () => history.state.firstLoadDone,
        why: () => 'History load',
      );
      await _until(
        () => activity.state.firstLoadDone,
        why: () => activity.state,
      );
    } on Object {
      await history.close();
      await activity.close();
      await attention.dispose();
      await sync.port.dispose();
      await accounts.dispose();
      await remote.close();
      rethrow;
    }
    return _Session._(
      remote,
      accounts,
      sync,
      attention,
      repository,
      history,
      activity,
    );
  }

  /// The pending forwarded Requests Activity offers, with their read state.
  /// They are not stream rows: Activity pins them above the stream.
  Future<Map<String, bool>> pendingForwardUnseen() async {
    final page = await repository.activityOffers();
    return {for (final row in page.items) row.beaconId: row.unseen};
  }

  Future<void> close() async {
    await history.close();
    await activity.close();
    await attention.dispose();
    await sync.port.dispose();
    await accounts.dispose();
    await remote.close();
  }
}

Future<void> _withServer(
  WidgetTester tester,
  Future<void> Function(ProductionReceiptTransport transport) body,
) =>
    tester.runAsync(() async {
          final transport = await ProductionReceiptTransport.start(
            activityRowsFixture: true,
          );
          try {
            await http.runWithClient(
              () => body(transport),
              () => MockClient((request) async {
                if (request.url.path.endsWith('/session/access-token')) {
                  return http.Response(
                    jsonEncode({
                      'subject': _viewer,
                      'access_token': 'test-token',
                      'expires_in': 3600,
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }
                return transport.graphql(
                  _viewer,
                  jsonDecode(request.body) as Map<String, dynamic>,
                );
              }),
            );
          } finally {
            await transport.close();
          }
        })
        as Future<void>;

Future<void> _expectActivityKept(
  _Session session, {
  required String reason,
}) async {
  final tombstone = session.activity.state.items.where(
    (r) => r.id == _tombstoneRowId,
  );
  expect(
    tombstone,
    hasLength(1),
    reason: '$reason: the tombstone row is still listed in Activity',
  );
  expect(tombstone.single.isSeen, isTrue, reason: '$reason: tombstone is read');
  final pending = await session.pendingForwardUnseen();
  expect(
    pending.keys,
    contains(_pendingBeaconId),
    reason: '$reason: pending forward is still in Activity',
  );
  expect(
    pending[_pendingBeaconId],
    isFalse,
    reason: '$reason: pending forward is read',
  );
}

Map<String, dynamic> _beaconWire(String at) => {
  '__typename': 'beacon',
  'id': _tombstoneBeaconId,
  'cover_source': 0,
  'title': 'Closed forwarded Request',
  'description': '',
  'needs': '',
  'created_at': at,
  'updated_at': at,
  'status': 1,
  'tags': '',
  'beacon_images': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'Ua00000000001',
    'display_name': 'Anna',
    'description': '',
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'active_help_offers': <dynamic>[],
  'participant_help_offers': <dynamic>[],
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_admitted_helper_aggregate',
    'aggregate': null,
  },
  'is_discoverable': false,
  'kind': 0,
  'forward_policy': 1,
  'last_activity_at': at,
  'viewer_can_forward': true,
  'can_read_content': true,
  'can_read_involvement': true,
  'can_read_admitted_helpers': true,
  'my_forward_edges': <dynamic>[],
};

/// Loads the viewer's tombstone InboxItem through the real [InboxRepository]
/// mapper, from the `inbox_item` row Postgres holds right now (the receipt
/// server does not speak Hasura, so the row is re-shaped as an InboxFetch
/// answer).
Future<void> _expectTombstoneNotDismissed(
  ProductionReceiptTransport transport, {
  required String reason,
}) async {
  final row = await transport.inboxItemRow(_viewer, _tombstoneBeaconId);
  expect(
    row['dismissedAt'],
    isNull,
    reason: '$reason: inbox_item.tombstone_dismissed_at stays NULL in Postgres',
  );
  final at = row['latestForwardAt'] as String;
  await withRemoteWire(
    {
      'InboxFetch': {
        '__typename': 'query_root',
        'inbox_item': [
          {
            '__typename': 'inbox_item',
            'beacon_id': _tombstoneBeaconId,
            'context': '',
            'forward_count': 1,
            'latest_forward_at': at,
            'latest_note_preview': '',
            'status': row['status'],
            'private_note': '',
            'rejection_message': '',
            'before_response_terminal_at': row['beforeResponseTerminalAt'],
            'tombstone_dismissed_at': row['dismissedAt'],
            'inbox_provenance_data': null,
            'beacon': _beaconWire(at),
          },
        ],
      },
      'InboxRoomContextBatch': {
        '__typename': 'query_root',
        'InboxRoomContextBatch': <dynamic>[],
      },
    },
    <WireSent>[],
    (remote) async {
      final items = await InboxRepository(
        remote,
        BeaconRoomHintsRepository(remote),
      ).fetch(userId: _viewer);
      expect(items, hasLength(1));
      expect(
        items.single.beforeResponseTerminalAt,
        isNotNull,
        reason: 'the fixture row is a tombstone',
      );
      expect(
        items.single.tombstoneDismissedAt,
        isNull,
        reason: '$reason: client InboxItem is not dismissed',
      );
    },
  );
}

void main() {
  testWidgets(
    'History Read all keeps the tombstone row and the pending forwarded '
    'Request in Activity and only reads them',
    (tester) async {
      await _withServer(tester, (transport) async {
        final session = await _Session.open();
        try {
          final before = session.activity.state.items.where(
            (r) => r.id == _tombstoneRowId,
          );
          expect(before, hasLength(1), reason: 'precondition: tombstone row');
          expect(before.single.isSeen, isFalse, reason: 'precondition: unread');
          expect(
            await session.pendingForwardUnseen(),
            {_pendingBeaconId: true},
            reason: 'precondition: pending forward is unread in Activity',
          );

          expect(await session.history.markAllSeen(), isTrue);
          // Straight after the call, before any refresh of Activity.
          await _expectActivityKept(session, reason: 'right after Read all');
          await _until(
            () => session.history.state.summary.unreadTotal == 0,
            why: () => session.history.state,
          );
          await session.activity.refresh();
          await _expectActivityKept(session, reason: 'after refresh');
          await _expectTombstoneNotDismissed(transport, reason: 'Read all');
        } finally {
          await session.close();
        }
      });
    },
  );

  testWidgets(
    'History Read all leaves History with no unread item and Read all '
    'disabled',
    (tester) async {
      await _withServer(tester, (transport) async {
        final session = await _Session.open();
        try {
          expect(await session.history.markAllSeen(), isTrue);
          await _until(
            () =>
                !session.history.state.canReadAll &&
                session.history.state.summary.unreadTotal == 0,
            why: () => session.history.state,
          );
          expect(
            session.history.state.items.where((r) => !r.isSeen),
            isEmpty,
          );
          expect(session.history.state.summary.unreadTotal, 0);
        } finally {
          await session.close();
        }
      });
    },
  );

  testWidgets(
    'no Activity state emitted while History Read all runs drops the '
    'tombstone row',
    (tester) async {
      await _withServer(tester, (transport) async {
        final session = await _Session.open();
        try {
          final frames = <List<String>>[];
          final sub = session.activity.stream.listen(
            (state) => frames.add([for (final r in state.items) r.id]),
          );
          expect(await session.history.markAllSeen(), isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await sub.cancel();
          expect(
            frames,
            isNotEmpty,
            reason: 'Read all moved the Activity feed',
          );
          for (final ids in frames) {
            expect(ids, contains(_tombstoneRowId));
          }
        } finally {
          await session.close();
        }
      });
    },
  );

  testWidgets(
    'after History Read all a freshly opened Activity still lists the '
    'tombstone row read and the pending forwarded Request',
    (tester) async {
      await _withServer(tester, (transport) async {
        final first = await _Session.open();
        try {
          expect(await first.history.markAllSeen(), isTrue);
        } finally {
          await first.close();
        }
        final reloaded = await _Session.open();
        try {
          await _expectActivityKept(reloaded, reason: 'after reload');
          await _expectTombstoneNotDismissed(transport, reason: 'reload');
        } finally {
          await reloaded.close();
        }
      });
    },
  );
}
