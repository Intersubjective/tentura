import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _requestId = 'Brequest00001';
const _postId = 'Bparentpost01';
const _requestTitle = 'Bring a ladder';
const _author = Profile(id: 'Ualice', displayName: 'Alice');
const _viewer = Profile(id: 'Uviewer000001', displayName: 'Омар');
final _createdAt = DateTime.utc(2026, 10, 20, 12);
const _relatedText =
    'Вы видите этот запрос, потому что участвуете в связанном запросе.';
const _deadline = Duration(seconds: 5);

const _emptyHelpOffers = {
  '__typename': 'beacon_help_offer_aggregate',
  'aggregate': null,
};

Map<String, dynamic> _beaconRead({required bool isPost}) => {
  '__typename': 'query_root',
  'beacon_by_pk': {
    '__typename': 'beacon',
    'viewer_can_forward': true,
    'cover_source': 0,
    'needs': '',
    'created_at': _createdAt.toIso8601String(),
    'updated_at': _createdAt.toIso8601String(),
    'status': 0,
    'tags': '',
    'beacon_images': <Object>[],
    'help_offers_aggregate': _emptyHelpOffers,
    'unanswered_help_offers': _emptyHelpOffers,
    'admitted_helpers_aggregate': _emptyHelpOffers,
    'is_discoverable': true,
    'id': isPost ? _postId : _requestId,
    'title': isPost ? '' : _requestTitle,
    'description': '',
    'author': {
      '__typename': 'user',
      'id': _author.id,
      'display_name': _author.displayName,
      'description': '',
    },
    'kind': isPost ? 1 : 0,
    'forward_policy': 1,
    'post_draft_attachments': <Object>[],
    'active_help_offers': <Object>[],
    'participant_help_offers': <Object>[],
    'admitted_helpers': <Object>[],
    'can_read_content': true,
    'can_read_involvement': false,
    'access_level': BeaconAccessLevel.observer.value,
    'access_reasons': isPost ? 0 : BeaconAccessReason.contextChild.bit,
  },
};

const _postSummary = {
  '__typename': 'v2_PostSummary',
  'id': _postId,
  'authorId': 'Ualice',
  'authorName': 'Alice',
  'authorAvatar': '',
  'rootImageUrl': null,
  'rootExcerpt': 'Garden volunteers',
  'lastMessageExcerpt': null,
  'lastMessageIsRoot': true,
  'lastMessageAt': null,
  'lastActivityAt': '2026-10-24T12:00:00.000Z',
  'pinnedAt': null,
  'mutedUntil': null,
  'mutedForever': false,
  'unreadCount': 0,
  'participantCount': 0,
  'notOpenedCount': 0,
  'myDeclinedForwardCount': 0,
  'previewParticipants': <Object>[],
  'isAuthor': false,
  'status': 0,
  'expiresAt': null,
};

void main() {
  testWidgets(
    'an observer opens a Request without looking up its access parent',
    (
      tester,
    ) async {
      final sent = <WireSent>[];
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      late BeaconViewCubit cubit;
      await tester.runAsync(() async {
        await withRemoteWire(
          const {},
          sent,
          (remote) async {
            final repository = BeaconRepository(remote, realtime.port);
            cubit = BeaconViewCubit(
              id: _requestId,
              myProfile: _viewer,
              beaconViewCase: buildTestBeaconViewCase(
                beaconRepo: repository,
                realtimeSyncCase: realtime.case_,
              ),
              effects: FakeUiEffectPort(),
            );
            addTearDown(() => tester.runAsync(repository.dispose));
            addTearDown(() => tester.runAsync(cubit.close));

            if (!cubit.state.beaconContextLoaded) {
              await cubit.stream
                  .firstWhere((state) => state.beaconContextLoaded)
                  .timeout(_deadline);
            }
            // Drain the background reads launched when Request content arrives.
            await pumpEventQueue();
          },
          responseFor: (call) async => switch (call.operationName) {
            'BeaconFetchById' => _beaconRead(
              isPost: call.variables['id'] == _postId,
            ),
            'BeaconParentReference' => {
              '__typename': 'query_root',
              'beaconParentReference': {
                '__typename': 'v2_BeaconParentReference',
                'state': 'available',
                'beaconId': _postId,
                'title': '',
                'isPost': true,
              },
            },
            'BeaconAdmittedHelpersRoster' || 'BeaconTeamAcquaintances' => {
              '__typename': 'query_root',
              'beacon_by_pk': {
                '__typename': 'beacon',
                'id': _requestId,
                'admitted_helpers': <Object>[],
              },
            },
            'PostSummary' => {
              '__typename': 'query_root',
              'postSummary': _postSummary,
            },
            _ => throw StateError(
              'Unexpected GraphQL operation: ${call.operationName}',
            ),
          },
        ).timeout(_deadline);
      });

      expect(cubit.state.beacon.id, _requestId);
      expect(cubit.state.beacon.accessLevel, BeaconAccessLevel.observer);
      expect(
        cubit.state.beacon.accessReasons,
        BeaconAccessReason.contextChild.bit,
      );
      final host = beaconViewHarnessHost(beaconId: _requestId);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        final closing = host.close();
        await tester.pump();
        await closing;
        await unregisterBeaconViewHarnessGetIt();
      });
      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        locale: const Locale('ru'),
        beaconState: cubit.state,
        beaconViewCubit: cubit,
        threadsState: beaconViewHarnessThreadsState(authorId: _author.id),
        host: host,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BeaconViewScreen), findsOneWidget);
      expect(find.text(_requestTitle), findsWidgets);
      expect(find.byType(RequestAccessReasonBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      final reads = [
        for (final call in sent)
          if (const {
            'BeaconFetchById',
            'BeaconParentReference',
            'PostSummary',
          }.contains(call.operationName))
            (
              call.operationName,
              call.variables['id'] ?? call.variables['beaconId'],
            ),
      ];
      expect(
        [
          (
            parent: cubit.state.accessParent,
            excerpt: cubit.state.accessParentPostExcerpt,
          ),
          reads,
          find.text(_relatedText).evaluate().length,
          find
              .byKey(const Key('request-access-reason-open-parent'))
              .evaluate()
              .length,
        ],
        [
          (parent: null, excerpt: ''),
          [('BeaconFetchById', _requestId)],
          1,
          0,
        ],
        reason: 'the Request response alone provides the access explanation',
      );
    },
  );
}
