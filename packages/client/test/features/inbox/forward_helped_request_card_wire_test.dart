import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/features/constellation/ui/util/constellation_forward_tree_request.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/remote_wire_harness.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _beaconId = 'b-774-activity';
const _title = 'Need a van';
const _annaId = 'u-anna';
const _borisId = 'u-boris';
const _kiraId = 'u-kira';
const _veraId = 'u-vera';

class _HarnessRouter extends Mock implements StackRouter {}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit() : super(const InboxState());

  @override
  void clearPendingMovedNudge() {}

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  Future<void> setWatching(String beaconId) async {}

  @override
  Future<void> stopWatching(String beaconId) async {}

  @override
  Future<void> dismiss(String beaconId, {String note = ''}) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

class _FakeProfileCubit implements ProfileCubit {
  _FakeProfileCubit(this.viewerId)
    : _state = ProfileState(
        profile: Profile(id: viewerId, displayName: 'V'),
      );

  final String viewerId;
  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => Stream.value(_state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Only the HTTP boundary is replaced. Receipt decoding, attention state,
// Activity cubits and the main feed/card are the production path.
Map<String, dynamic> _receipt({bool done = false}) => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'helped-receipt',
  'category': 'coordination',
  'kind': 'commitmentEvent',
  'priority': 'normal',
  'title': 'Your forward helped',
  'body': '',
  'actionUrl': '/#/view/$_beaconId',
  'createdAt': '2026-11-11T12:00:00Z',
  'collapsedCount': 1,
  'beaconId': _beaconId,
  'beaconTitle': _title,
  'beaconKind': 0,
  'beaconAuthorId': _annaId,
  'beaconAuthorName': 'Anna',
  'actorUserId': null,
  'targetEntityId': _veraId,
  'presentationKey': 'forward_helped',
  'presentationPayloadJson': jsonEncode({
    'eventType': 'forwardHelped',
    'personal': false,
    'beaconId': _beaconId,
    'beaconTitle': _title,
    'authorId': _annaId,
    'helperId': _veraId,
    'done': done,
    'path': [
      {'userId': _annaId, 'displayName': 'Anna', 'anonymousCount': 0},
      {'userId': _borisId, 'displayName': 'Boris', 'anonymousCount': 0},
      {'userId': _kiraId, 'displayName': 'Kira', 'anonymousCount': 0},
      {'userId': _veraId, 'displayName': 'Vera', 'anonymousCount': 0},
    ],
  }),
  'requiresAction': false,
  'surface': 'activity',
  'itemKind': 'receipt',
  'allowsForward': !done,
  'eventsPreview': <Object?>[],
};

final class _Server {
  bool closed = false;
  bool cleared = false;
  final dismissedIds = <String>[];

  List<Map<String, dynamic>> get events => [
    if (!cleared) _receipt(done: closed),
    {
      ..._receipt(),
      'id': 'newer-status',
      'title': 'Request status changed',
      'createdAt': '2026-11-11T13:00:00Z',
      'presentationKey': 'request_status_changed',
      'presentationPayloadJson': jsonEncode({
        'eventType': 'requestStatusChanged',
        'personal': false,
        'toStatus': closed ? 'closed' : 'open',
      }),
    },
    {
      ..._receipt(),
      'id': 'other-sender-message',
      'title': 'Can bring a trolley',
      'body': 'Can bring a trolley',
      'createdAt': '2026-11-11T12:02:00Z',
      'actorUserId': _kiraId,
      'presentationKey': 'room_message_posted',
      'presentationPayloadJson':
          '{"eventType":"roomMessagePosted","personal":true,"excerpt":"Can bring a trolley"}',
    },
    if (closed)
      {
        ..._receipt(),
        'id': 'closed-receipt',
        'presentationKey': 'closure_finalized',
        'presentationPayloadJson': '{"eventType":"closureFinalized"}',
      },
  ];

  Future<Map<String, dynamic>> respond(WireSent request) async {
    switch (request.operationName) {
      case 'ActivityOffersV2':
        return {
          '__typename': 'query_root',
          'activityOffers': {
            '__typename': 'v2_ActivityOfferPage',
            'totalCount': closed ? 0 : 1,
            'nextCursor': null,
            'items': [
              if (!closed)
                {
                  '__typename': 'v2_ActivityOfferSortRow',
                  'beaconId': _beaconId,
                  'listPositionAt': '2026-11-11T11:00:00Z',
                  'effectiveActivityAt': '2026-11-11T12:00:00Z',
                  'latestForwardAt': '2026-11-11T11:00:00Z',
                  'unseen': !cleared,
                  'declinedInvite': false,
                  'eventTotal': events.length,
                  'eventUnseenCount': events.length,
                  'eventsPreview': events,
                },
            ],
          },
        };
      case 'AttentionFeed':
        return {
          '__typename': 'query_root',
          'attentionFeed': {
            '__typename': 'v2_AttentionFeed',
            'summary': {
              '__typename': 'v2_AttentionSummary',
              'unreadTotal': cleared ? 0 : 1,
              'needsYouTotal': 0,
            },
            'page': {
              '__typename': 'v2_AttentionPage',
              'nextCursor': null,
              'items': [
                if (closed && !cleared)
                  {
                    ..._receipt(done: true),
                    'id': 'activity-$_beaconId',
                    'itemKind': 'requestActivity',
                    'title': _title,
                    'presentationKey': 'request_status_changed',
                    'presentationPayloadJson': '{}',
                    'eventTotal': events.length,
                    'eventUnseenCount': events.length,
                    'eventsPreview': events,
                  },
              ],
            },
          },
        };
      case 'AttentionSurfaceSummary':
        return {
          '__typename': 'query_root',
          'attentionSurfaceSummary': {
            '__typename': 'v2_AttentionSurfaceSummary',
            'unreadTotal': cleared ? 0 : 1,
            'needsYouTotal': 0,
            'myDeskDot': false,
            'myDeskCount': 0,
            'forYouDot': !cleared,
            'forYouSweepEligible': !cleared,
          },
        };
      case 'AttentionMarkers':
        return {
          'attentionMarkers': {'unreadBeaconIds': <String>[]},
        };
      case 'AttentionLiveObligations':
        return {'liveObligationBeacons': <String>[]};
      case 'AttentionClearSnapshot':
        expect(request.variables['receiptId'], 'helped-receipt');
        return {
          'attentionClearSnapshot': {
            'snapshotToken': 'helped-snapshot',
            'receiptIds': ['helped-receipt'],
            'outcomeGeneration': 0,
            'decisionRevision': 0,
          },
        };
      case 'AttentionClear':
        dismissedIds.add('helped-receipt');
        cleared = true;
        return {
          'attentionClear': {
            'operationId': request.variables['operationId'],
            'appliedReceiptIds': ['helped-receipt'],
            'skippedReceiptIds': <String>[],
            'deniedReceiptIds': <String>[],
            'status': 'complete',
          },
        };
      default:
        throw StateError('Unexpected operation: ${request.operationName}');
    }
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _helpedRow() => find.descendant(
  of: find.byType(RequestAttentionCard),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is AttentionMiniCard && widget.receipt.id == 'helped-receipt',
  ),
);

void _expectRow(
  WidgetTester tester,
  String headline,
  String action, {
  bool done = false,
}) {
  final row = _helpedRow();
  expect(
    row,
    findsOneWidget,
    reason: 'the main Activity Request card owns this receipt',
  );
  expect(
    find.descendant(of: row, matching: find.text(headline)),
    findsOneWidget,
  );
  final card = find.byType(RequestAttentionCard);
  final zone = find.descendant(
    of: card,
    matching: find.byKey(RequestAttentionCard.forYouZoneKey),
  );
  final change = find.descendant(
    of: card,
    matching: find.byKey(RequestAttentionCard.changeLineKey),
  );
  final otherSender = find.descendant(
    of: card,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AttentionMiniCard &&
          widget.receipt.id == 'other-sender-message',
    ),
  );
  expect(zone, findsOneWidget);
  expect(change, findsOneWidget);
  expect(otherSender, findsOneWidget);
  expect(find.ancestor(of: row, matching: zone), findsOneWidget);
  expect(find.ancestor(of: otherSender, matching: zone), findsOneWidget);
  expect(
    find.descendant(of: change, matching: find.text(headline)),
    findsNothing,
  );
  final l10n = L10n.of(tester.element(card))!;
  expect(
    find.descendant(
      of: change,
      matching: find.text(
        l10n.attentionEventStatusChanged(
          done
              ? l10n.requestStatusActivityClosed
              : l10n.requestStatusActivityOpen,
        ),
      ),
    ),
    findsOneWidget,
  );
  expect(
    tester.getRect(row).bottom,
    lessThanOrEqualTo(tester.getRect(change).top),
  );
  expect(
    tester.getRect(row).overlaps(tester.getRect(otherSender)),
    isFalse,
    reason: 'the forwarder receipt and another sender have separate rows',
  );
  final fieldAction = find.descendant(of: row, matching: find.text(action));
  expect(
    fieldAction.hitTestable(),
    findsOneWidget,
    reason: 'Show on Field is visible and accepts a tap at this viewport',
  );
  final dismiss = find.descendant(
    of: row,
    matching: find.byKey(AttentionMiniCard.dismissKey),
  );
  expect(
    dismiss,
    findsOneWidget,
    reason: 'an actorless forward-helped receipt still has its own visible ×',
  );
  expect(
    dismiss.hitTestable(),
    findsOneWidget,
    reason: 'the dismiss target is visible and accepts a tap at this viewport',
  );
  final closeIcon = tester.widget<Icon>(
    find.descendant(of: dismiss, matching: find.byIcon(Icons.close)),
  );
  expect(closeIcon.semanticLabel?.trim(), isNotEmpty);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final surface in [
    (size: kPhoneSurface, locale: const Locale('en')),
    (size: kPhoneSurface, locale: const Locale('ru')),
    (size: const Size(1280, 800), locale: const Locale('en')),
    (size: const Size(1280, 800), locale: const Locale('ru')),
  ]) {
    testWidgets(
      'a forwarder can dismiss an accepted receipt on the main Activity card '
      'and receive its completed receipt after close at ${surface.size} ${surface.locale}',
      (tester) async {
        tester.view
          ..physicalSize = surface.size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.binding.setSurfaceSize(surface.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final server = _Server();
        final sent = <WireSent>[];
        await tester.runAsync(
          () => withRemoteWire({}, sent, (remote) async {
            final accounts = _Accounts();
            final sync = buildTestRealtimeSync();
            final actors = buildNoopAttentionActorProfiles();
            final logger = Logger('forward-helped-request-card');
            final attention = AttentionCase(
              AttentionRepository(remote),
              accounts,
              sync.case_,
              noopBlockCase(),
              FeedSessionRegistry(),
              logger,
            );
            final inbox = FakeInboxRepository()
              ..inboxItemsByBeacon = {
                _beaconId: InboxItem(
                  beaconId: _beaconId,
                  latestForwardAt: DateTime.utc(2026, 11, 11),
                  isForwardedByMe: true,
                  beacon: Beacon(
                    id: _beaconId,
                    title: _title,
                    author: const Profile(id: _annaId, displayName: 'Anna'),
                    createdAt: DateTime.utc(2026, 11),
                    updatedAt: DateTime.utc(2026, 11, 11),
                  ),
                ),
              };
            final offers = ActivityOffersCubit(
              userId: _borisId,
              inboxCase: buildTestInboxCase(
                inbox,
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
            final inboxCubit = _TestInboxCubit();
            final navigation = FakeUiEffectPort();
            final screen = ScreenCubit(navigation);
            GetIt.I.registerSingleton<AttentionCase>(attention);
            GetIt.I.registerSingleton<ProfileCubit>(
              _FakeProfileCubit(_borisId),
            );
            registerFakeAppNavigator();
            accounts.emit(_borisId);
            Future<void> reload() async {
              await offers.loadFirst();
              await stream.refresh();
              await _frames(tester);
              expect(
                offers.state.pageLoadError,
                isNull,
                reason: 'wire operations: $sent',
              );
              expect(stream.state.refreshError, isNull);
            }

            try {
              await reload();
              await tester.pumpWidget(
                StackRouterScope(
                  controller: _HarnessRouter(),
                  stateHash: 0,
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<ActivityOffersCubit>.value(value: offers),
                      BlocProvider<UpdatesFeedCubit>.value(value: stream),
                      BlocProvider<InboxCubit>.value(value: inboxCubit),
                      BlocProvider<ScreenCubit>.value(value: screen),
                    ],
                    child: MaterialApp(
                      locale: surface.locale,
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
              await _frames(tester);
              expect(find.byType(RequestAttentionCard), findsOneWidget);
              expect(
                MediaQuery.sizeOf(
                  tester.element(find.byType(RequestAttentionCard)),
                ),
                surface.size,
              );
              expect(
                offers.state.eventsByBeacon[_beaconId]?.eventsPreview
                    .singleWhere((receipt) => receipt.id == 'helped-receipt')
                    .actorUserId,
                isNull,
              );
              final ru = surface.locale.languageCode == 'ru';
              final headline = ru
                  ? '✨ Ваша пересылка помогла'
                  : '✨ Your forward helped';
              final action = ru ? 'Показать на поле ›' : 'Show on Field ›';
              // Verify the public action's open-Request destination before
              // asserting the independently missing dismiss control.
              final fieldAction = find.descendant(
                of: _helpedRow(),
                matching: find.text(action),
              );
              expect(fieldAction, findsOneWidget);
              await tester.tap(fieldAction);
              await _frames(tester);
              expect(
                navigation.emitted.whereType<NavigatePush>().last.path,
                kPathConstellation,
              );
              final target = ConstellationForwardTreeRequest.instance.take();
              expect(target?.beaconId, _beaconId);
              expect(target?.helpOffererId, _veraId);
              _expectRow(tester, headline, action);
              await tester.tap(
                find.descendant(
                  of: _helpedRow(),
                  matching: find.byKey(AttentionMiniCard.dismissKey),
                ),
              );
              await _frames(tester);
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await _frames(tester);
              expect(server.dismissedIds, ['helped-receipt']);
              expect(_helpedRow(), findsNothing);
              await reload();
              expect(
                _helpedRow(),
                findsNothing,
                reason: 'reload cannot resurrect the accepted receipt',
              );
              // The server sends a fresh uncleared Done variant after finalization.
              server
                ..closed = true
                ..cleared = false;
              await reload();
              _expectRow(
                tester,
                '$headline · ${ru ? 'Готово' : 'Done'} ✓',
                action,
                done: true,
              );
              await tester.tap(
                find.descendant(
                  of: _helpedRow(),
                  matching: find.text(action),
                ),
              );
              await _frames(tester);
              final closedTarget = Uri.parse(
                navigation.emitted.whereType<NavigatePush>().last.path,
              );
              expect(closedTarget.path, '$kPathBeaconView/$_beaconId');
              expect(
                closedTarget.queryParameters[kQueryBeaconEntry],
                kBeaconEntryInbox,
              );
              await tester.tap(
                find.descendant(
                  of: _helpedRow(),
                  matching: find.byKey(AttentionMiniCard.dismissKey),
                ),
              );
              await _frames(tester);
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await reload();
              expect(server.dismissedIds, ['helped-receipt', 'helped-receipt']);
              expect(
                _helpedRow(),
                findsNothing,
                reason: 'closed receipt stays dismissed after reload',
              );
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await offers.close();
              await stream.close();
              await screen.close();
              await inboxCubit.close();
              unawaited(attention.dispose());
              unawaited(accounts.close());
              unawaited(sync.port.dispose());
              await GetIt.I.reset();
            }
          }, responseFor: server.respond),
        );
      },
    );
  }
}
