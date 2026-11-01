// #258 round 3 (review of PR #935): Updates «Read all» must give the same
// answer on «Все» and «Непрочитанные». Dismiss all (For you) clears the shared
// Posts (`cleared_at`) but does not read them (`seen_at` stays null), so the
// All page keeps them as cleared-but-unseen rows that are not on Unread. The
// gate read those rows as "unseen, Read all has work" and stayed enabled on
// «Все» while «Непрочитанные» (only the read forwards) was disabled.
//
// Real path: the server's wire rows → Ferry → AttentionRepository →
// AttentionCase → UpdatesFeedCubit.state.canReadAll, on both filters.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'support/noop_invite_setup_port.dart';

const _readAt = '2026-11-01T09:00:00.000Z';
const _sweptAt = '2026-11-01T10:00:00.000Z';

Map<String, dynamic> _wireReceipt({
  required String id,
  required String kind,
  required String presentationKey,
  required String beaconId,
  required int beaconKind,
  String? seenAt,
  String? clearedAt,
  String? clearReason,
}) => {
  '__typename': 'v2_AttentionReceipt',
  'id': id,
  'category': 'requestProgress',
  'kind': kind,
  'priority': 'low',
  'title': 'Q1101 Alice',
  'body': 'Q1101 Alice',
  'actionUrl': '/#/beacon/view/$beaconId',
  'createdAt': '2026-11-01T08:00:00.000Z',
  'seenAt': seenAt,
  'collapsedCount': 1,
  'beaconId': beaconId,
  'coordinationItemId': null,
  'actorUserId': 'Ualice000000001',
  'sourceEventKey': '$kind:$beaconId',
  'destinationKind': 'beacon',
  'targetEntityId': null,
  'presentationKey': presentationKey,
  'presentationPayloadJson': '{"personal":true}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': clearedAt,
  'clearReason': clearReason,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': null,
  'beaconAuthorName': null,
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': null,
  'beaconTitle': null,
  'beaconKind': beaconKind,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': <Object?>[],
};

/// An unanswered forward the viewer has read: on Unread (not cleared), and
/// never cleared by Read all (the forward shell).
Map<String, dynamic> _forward(int i) => _wireReceipt(
  id: 'Nforward00000$i',
  kind: 'newRelay',
  presentationKey: 'relay_received',
  beaconId: 'Brequest0000$i',
  beaconKind: 0,
  seenAt: _readAt,
);

/// A shared Post as Dismiss all leaves it: cleared, never read.
Map<String, dynamic> _sweptPost(int i) => _wireReceipt(
  id: 'Npost0000000$i',
  kind: 'postShared',
  presentationKey: 'post_shared',
  beaconId: 'Bpost000000$i',
  beaconKind: 1,
  clearedAt: _sweptAt,
  clearReason: 'sweep',
);

/// A shared Post nobody has read or cleared yet.
Map<String, dynamic> _freshPost() => _wireReceipt(
  id: 'Npostfresh0001',
  kind: 'postShared',
  presentationKey: 'post_shared',
  beaconId: 'Bpostfresh001',
  beaconKind: 1,
);

Map<String, dynamic> _feed(List<Map<String, dynamic>> items, int unread) => {
  '__typename': 'query_root',
  'attentionFeed': {
    '__typename': 'v2_AttentionFeed',
    'summary': {
      '__typename': 'v2_AttentionSummary',
      'unreadTotal': unread,
      'needsYouTotal': 0,
    },
    'page': {
      '__typename': 'v2_AttentionPage',
      'nextCursor': null,
      'items': items,
    },
  },
};

Map<String, dynamic> _surfaceSummary({required bool sweepEligible}) => {
  '__typename': 'query_root',
  'attentionSurfaceSummary': {
    '__typename': 'v2_AttentionSurfaceSummary',
    'myDeskDot': false,
    'myDeskCount': 0,
    'forYouDot': sweepEligible,
    'forYouSweepEligible': sweepEligible,
  },
};

Future<void> _until(bool Function() done, String what) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('timed out waiting for $what');
}

/// Opens Updates on «Все», then switches to «Непрочитанные». The server
/// answers each view with its own page; returns `canReadAll` on each.
Future<({bool all, bool unread})> _readAllOnBothFilters({
  required List<Map<String, dynamic>> allPage,
  required List<Map<String, dynamic>> unreadPage,
}) async {
  final unreadTotal = unreadPage.length;
  final responses = <String, Map<String, dynamic>>{
    'AttentionFeed': _feed(allPage, unreadTotal),
    'AttentionSurfaceSummary': _surfaceSummary(sweepEligible: false),
  };
  final sent = <WireSent>[];
  late bool onAll;
  late bool onUnread;
  await withRemoteWire(responses, sent, (remote) async {
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      AttentionRepository(remote),
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('issue-258-mixed'),
    );
    final cubit = UpdatesFeedCubit(
      destinationId: AttentionFeedDestinationId.activityStream,
      attention: attention,
      setup: NoopInviteAcceptedSetupPort(),
      realtime: sync.case_,
      logger: Logger('issue-258-mixed-cubit'),
      actorProfiles: buildNoopAttentionActorProfiles(),
    );
    try {
      accounts.emit('Uviewer000001');
      await _until(
        () =>
            cubit.state.view == AttentionView.all &&
            cubit.state.items.length == allPage.length,
        'the «Все» page',
      );
      onAll = cubit.state.canReadAll;

      responses['AttentionFeed'] = _feed(unreadPage, unreadTotal);
      final sentBefore = sent.length;
      await cubit.setView(AttentionView.unread);
      await _until(
        () =>
            sent
                .skip(sentBefore)
                .any(
                  (s) =>
                      s.operationName == 'AttentionFeed' &&
                      s.variables['view'] == 'unread',
                ) &&
            cubit.state.view == AttentionView.unread &&
            cubit.state.items.length == unreadPage.length,
        'the «Непрочитанные» page',
      );
      onUnread = cubit.state.canReadAll;
    } finally {
      await cubit.close();
      await attention.dispose();
      await sync.port.dispose();
      await accounts.close();
    }
  });
  return (all: onAll, unread: onUnread);
}

void main() {
  final forwards = [for (var i = 0; i < 6; i++) _forward(i)];

  test('forwards + shared Posts, after Dismiss all: Read all is disabled on '
      'both «Все» and «Непрочитанные»', () async {
    final result = await _readAllOnBothFilters(
      allPage: [for (var i = 0; i < 6; i++) _sweptPost(i), ...forwards],
      unreadPage: forwards,
    );
    expect(result.unread, isFalse, reason: '«Непрочитанные»: only forwards');
    expect(
      result.all,
      isFalse,
      reason:
          '«Все»: the swept Posts are not on Unread, so Read all has '
          'nothing to do there either',
    );
  });

  test('a genuinely unread Post beside them keeps Read all enabled on both '
      'filters', () async {
    final result = await _readAllOnBothFilters(
      allPage: [
        _freshPost(),
        for (var i = 0; i < 6; i++) _sweptPost(i),
        ...forwards,
      ],
      unreadPage: [_freshPost(), ...forwards],
    );
    expect(result.all, isTrue);
    expect(result.unread, isTrue);
  });
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}
