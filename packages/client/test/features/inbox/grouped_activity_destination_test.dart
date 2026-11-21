import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_case_factory.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _postId = 'post-1';
const _requestId = 'request-1';

class _SignedInAccount implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value('viewer');
}

class _RouterScope extends Mock implements StackRouter {}

class _Inbox extends Cubit<InboxState> implements InboxCubit {
  _Inbox() : super(const InboxState(projectionLoaded: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _receipt(String id, String beaconId) => {
  '__typename': 'v2_AttentionReceipt',
  'id': id,
  'category': 'coordination',
  'kind': 'roomActivityLowPriority',
  'priority': 'normal',
  'title': 'Activity',
  'body': '',
  'actionUrl': '/#/view?id=$beaconId',
  'createdAt': '2026-11-11T12:00:00Z',
  'collapsedCount': 1,
  'beaconId': beaconId,
  'beaconTitle': 'Книжный обмен',
  'beaconKind': beaconId == _postId ? 1 : 0,
  'beaconAuthorId': 'anna',
  'beaconAuthorName': 'Анна',
  'surface': 'activity',
  'requiresAction': false,
};

Map<String, Object?> _event(
  String target, {
  String beaconId = _postId,
  int minute = 0,
  String kind = 'roomActivityLowPriority',
  String eventType = 'roomMessagePosted',
  String presentationKey = 'room_message_posted',
  String destinationKind = 'beacon_room_message',
  String excerpt = 'Я принесу книгу',
  String? actorName,
}) => {
  ..._receipt('event-$target', beaconId),
  'itemKind': 'receipt',
  'kind': kind,
  'body': excerpt,
  'createdAt': DateTime.utc(2026, 11, 11, 12, minute).toIso8601String(),
  'destinationKind': destinationKind,
  'targetEntityId': target,
  'actorUserId': 'boris',
  'presentationKey': presentationKey,
  'presentationPayloadJson': jsonEncode({
    'eventType': eventType,
    'personal': true,
    'excerpt': excerpt,
    'actorName': ?actorName,
  }),
};

Map<String, Object?> _group(
  String beaconId,
  List<Map<String, Object?>> events,
) => {
  ..._receipt('group-$beaconId', beaconId),
  'title': 'Книжный обмен',
  'postRootExcerpt': 'Книжный обмен',
  'itemKind': 'requestActivity',
  'collapsedCount': 0,
  'presentationKey': 'request_status_changed',
  'destinationKind': 'beacon',
  'targetEntityId': beaconId,
  'eventTotal': events.length,
  'eventUnseenCount': events.length,
  'presentationPayloadJson': '{}',
  'eventsPreview': events,
};

Map<String, Map<String, dynamic>> _responses(
  List<Map<String, Object?>> groups,
) => {
  'AttentionFeed': {
    'attentionFeed': {
      '__typename': 'v2_AttentionFeed',
      'summary': {
        '__typename': 'v2_AttentionSummary',
        'unreadTotal': groups.length,
        'needsYouTotal': 0,
      },
      'page': {
        '__typename': 'v2_AttentionPage',
        'items': groups,
      },
    },
  },
  'AttentionSurfaceSummary': {
    'attentionSurfaceSummary': {
      '__typename': 'v2_AttentionSurfaceSummary',
      'unreadTotal': groups.length,
      'needsYouTotal': 0,
      'myDeskDot': false,
      'myDeskCount': 0,
      'forYouDot': true,
      'forYouSweepEligible': false,
      'forYouReceiptSweepEligible': false,
    },
  },
  'ActivityOffersV2': {
    'activityOffers': {
      '__typename': 'v2_ActivityOfferPage',
      'totalCount': 0,
      'items': <Object>[],
    },
  },
};

Future<void> _withActivity(
  WidgetTester tester,
  List<Map<String, Object?>> groups,
  Future<void> Function(FakeAppNavigator navigator) check,
) async {
  tester.view
    ..physicalSize = kPhoneSurface
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await usePhoneSurface(tester);
  final sent = <WireSent>[];
  await tester.runAsync(
    () => withRemoteWire(_responses(groups), sent, (remote) async {
      final sync = buildTestRealtimeSync();
      final logger = Logger('ActivityDestinationTest');
      final actors = buildNoopAttentionActorProfiles();
      final attention = buildAttentionCase(
        repository: AttentionRepository(remote),
        accounts: _SignedInAccount(),
        realtimeSyncCase: sync.case_,
        logger: logger,
      );
      final offers = ActivityOffersCubit(
        userId: 'viewer',
        inboxCase: buildTestInboxCase(
          FakeInboxRepository(),
          buildTestBeaconThreadsCase(),
        ),
        attentionCase: attention,
        actorProfiles: actors,
        effects: FakeUiEffectPort(),
      );
      final stream = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        actorProfiles: actors,
        setup: NoopInviteAcceptedSetupPort(),
        realtime: sync.case_,
        logger: logger,
      );
      final inbox = _Inbox();
      final screen = ScreenCubit(FakeUiEffectPort());
      final navigator = registerFakeAppNavigator();

      try {
        await offers.loadFirst();
        await stream.refresh();
        expect(offers.state.pageLoadError, isNull, reason: 'Requests: $sent');
        expect(stream.state.refreshError, isNull, reason: 'Requests: $sent');
        expect(
          sent.map((request) => request.operationName),
          contains('AttentionFeed'),
        );

        if (!stream.state.firstLoadDone) {
          await stream.stream
              .firstWhere((state) => state.firstLoadDone)
              .timeout(const Duration(seconds: 2));
        }
        await tester.pumpWidget(
          StackRouterScope(
            controller: _RouterScope(),
            stateHash: 0,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ActivityOffersCubit>.value(value: offers),
                BlocProvider<UpdatesFeedCubit>.value(value: stream),
                BlocProvider<InboxCubit>.value(value: inbox),
                BlocProvider<ScreenCubit>.value(value: screen),
              ],
              child: MaterialApp(
                locale: const Locale('ru'),
                theme: TenturaTheme.light(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: const TenturaResponsiveScope(
                  child: Scaffold(body: ActivityStreamView()),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          MediaQuery.sizeOf(tester.element(find.byType(ActivityStreamView))),
          kPhoneSurface,
        );
        await check(navigator);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await offers.close();
        await stream.close();
        await screen.close();
        await inbox.close();
        unawaited(attention.dispose());
        unawaited(sync.port.dispose());
        await GetIt.I.reset();
      }
    }),
  );
}

Future<AttentionReceipt> _tapAndReadReceipt(
  WidgetTester tester,
  Finder target,
  FakeAppNavigator navigator,
) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  final before = navigator.openedReceipts.length;
  await tester.tap(target);
  await tester.pump();
  expect(navigator.openedReceipts, hasLength(before + 1));
  expect(tester.takeException(), isNull);
  return navigator.openedReceipts.last;
}

Future<AttentionReceipt> _tapPostGroup(
  WidgetTester tester,
  Finder target,
  FakeAppNavigator navigator,
) async {
  final receipt = await _tapAndReadReceipt(tester, target, navigator);
  expect(receipt.id, 'group-post-1');
  expect(receipt.itemKind, AttentionItemKind.requestActivity);
  return receipt;
}

Finder _postHeadline(String text) => find.descendant(
  of: find.byType(PostAttentionRow),
  matching: find.text(text),
);

void _expectPostMessage(AttentionReceipt group, String messageId) {
  expect(
    group.eventsPreview.where(
      (event) =>
          event.destinationKind == 'beacon_room_message' &&
          event.beaconId == _postId &&
          event.targetEntityId == messageId,
    ),
    hasLength(1),
    reason: 'The message in the link comes from the Post group preview',
  );
  final link = attentionDestination(group);
  expect(link.path, '/post/view/post-1');
  expect(link.queryParameters, {'tab': 'threads', 'message': messageId});
}

void main() {
  testWidgets('a Post with one chat event opens that message while a Request '
      'chat event still opens its Request', (tester) async {
    await _withActivity(
      tester,
      [
        _group(_postId, [_event('M1')]),
        _group(_requestId, [_event('request-message', beaconId: _requestId)]),
      ],
      (navigator) async {
        final post = await _tapPostGroup(
          tester,
          _postHeadline('Пост · вам ответили'),
          navigator,
        );
        final requestEvent = find.descendant(
          of: find.byType(RequestAttentionCard),
          matching: find.byType(AttentionMiniCard),
        );
        final request = await _tapAndReadReceipt(
          tester,
          requestEvent,
          navigator,
        );
        expect(request.id, 'group-$_requestId');
        expect(
          attentionDestination(request).toString(),
          '/beacon/view/request-1',
        );
        _expectPostMessage(post, 'M1');
      },
    );
  });

  testWidgets('the newest Post reply supplies both the headline and the link', (
    tester,
  ) async {
    await _withActivity(
      tester,
      [
        _group(_postId, [
          _event('M1', actorName: 'Борис'),
          _event('M2', minute: 1, actorName: 'Вера'),
        ]),
      ],
      (navigator) async {
        expect(_postHeadline('Борис отвечает на ваш пост'), findsNothing);
        final group = await _tapPostGroup(
          tester,
          _postHeadline('Вера отвечает на ваш пост'),
          navigator,
        );
        _expectPostMessage(group, 'M2');
      },
    );
  });

  for (final scenario in [
    (
      name: 'mention',
      message: 'M3',
      kind: 'roomMention',
      eventType: 'roomMessagePosted',
      key: 'room_message_posted',
      headline: 'Пост · вас упомянули',
    ),
    (
      name: 'first response',
      message: 'M4',
      kind: 'postFirstResponse',
      eventType: 'postFirstResponse',
      key: 'post_first_response',
      headline: 'На ваш пост откликнулись',
    ),
  ]) {
    testWidgets('a Post opens the message behind its newest ${scenario.name}', (
      tester,
    ) async {
      await _withActivity(
        tester,
        [
          _group(_postId, [
            _event(
              scenario.message,
              minute: 1,
              kind: scenario.kind,
              eventType: scenario.eventType,
              presentationKey: scenario.key,
            ),
            _event('M1'),
          ]),
        ],
        (navigator) async {
          final group = await _tapPostGroup(
            tester,
            _postHeadline(scenario.headline),
            navigator,
          );
          _expectPostMessage(group, scenario.message);
        },
      );
    });
  }

  testWidgets('a Post opens its newest message only when the latest event '
      'points to one', (tester) async {
    final openedGroups = <String, AttentionReceipt>{};
    for (final (name, events) in [
      ('reply', [_event('M1')]),
      (
        'expiry',
        [
          _event('M1'),
          _event(
            _postId,
            minute: 1,
            kind: 'postExpiringSoon',
            eventType: 'postExpiringSoon',
            presentationKey: 'post_expiring_soon',
            destinationKind: 'beacon',
          ),
        ],
      ),
      ('empty', <Map<String, Object?>>[]),
    ]) {
      await _withActivity(tester, [_group(_postId, events)], (navigator) async {
        final target = name == 'expiry'
            ? _postHeadline('Пост скоро закроется')
            : find.byType(PostAttentionRow);
        openedGroups[name] = await _tapPostGroup(
          tester,
          target,
          navigator,
        );
      });
    }
    for (final name in ['expiry', 'empty']) {
      expect(
        attentionDestination(openedGroups[name]!).toString(),
        '/post/view/post-1',
      );
    }
    _expectPostMessage(openedGroups['reply']!, 'M1');
  });
}
