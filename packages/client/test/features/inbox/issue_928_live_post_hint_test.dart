// #928: a hierarchy-delivery room_message on a Post must not pin it as a
// titleless Request card while Activity stays open. Live refresh uses the v2
// single-row lookup (Request kind only), not the legacy inbox open-forward row.

import 'dart:async';

import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_invite_card.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'author_invite_test_support.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _postId = 'Bpost000000001';
const _requestId = 'Brequest00001';
const _requestTitle = 'Book swap Sunday';

Future<void> _settleDesk(WidgetTester tester) async {
  // Advance past the cubit's 50 ms desk-relevance debounce (fake-async safe).
  await tester.pump(const Duration(milliseconds: 60));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

RealtimeEntityChange _roomMessageHint(String beaconId) => RealtimeEntityChange(
  kind: RealtimeEntityKind.roomMessage,
  aggregateId: beaconId,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

InboxItem _legacyOpenPostInboxRow() {
  final at = DateTime.utc(2026, 10, 24, 17);
  return InboxItem(
    beaconId: _postId,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
    beacon: Beacon(
      id: _postId,
      title: '',
      kind: BeaconKind.post,
      author: const Profile(id: 'alice', displayName: 'Alice'),
      createdAt: at,
      updatedAt: at,
      viewerCanForward: true,
    ),
  );
}

InboxItem _requestInboxItem({BeaconStatus status = BeaconStatus.open}) {
  final at = DateTime.utc(2026, 10, 24, 16);
  return InboxItem(
    beaconId: _requestId,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
    beacon: Beacon(
      id: _requestId,
      title: _requestTitle,
      kind: BeaconKind.request,
      status: status,
      author: const Profile(id: 'alice', displayName: 'Alice'),
      createdAt: at,
      updatedAt: at,
      viewerCanForward: status.allowsForward,
    ),
  );
}

ActivityOfferSortRow _requestOfferRow({
  String? inviteId,
  bool declinedInvite = false,
}) {
  final item = _requestInboxItem();
  return activityOfferSortRow(item).copyWith(
    inviteId: inviteId,
    declinedInvite: declinedInvite,
  );
}

final class Issue928AttentionRepo
    extends ConfigurableActivityOffersAttentionRepo {
  Issue928AttentionRepo(this.streamItems);

  final List<AttentionReceipt> streamItems;

  @override
  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
    String? beaconId,
  }) async {
    if (beaconId == _postId) {
      beaconOfferLookups.add(beaconId!);
      return const ActivityOfferPage(items: [], totalCount: 0);
    }
    return super.activityOffers(
      cursor: cursor,
      limit: limit,
      beaconId: beaconId,
    );
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: const AttentionSummary(),
    page: AttentionFeedPage(
      items: cursor == null || cursor.isEmpty ? streamItems : const [],
    ),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

class _HarnessRouter extends Mock implements StackRouter {}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initialState);

  @override
  Future<bool> fetch({bool showLoading = true, bool showError = true}) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({
    required this.offers,
    required this.stream,
    required this.attention,
    required this.sync,
    required this.inboxRepo,
    required this.attentionRepo,
  });

  final ActivityOffersCubit offers;
  final UpdatesFeedCubit stream;
  final AttentionCase attention;
  final TestRealtimeSyncPort sync;
  final FakeInboxRepository inboxRepo;
  final Issue928AttentionRepo attentionRepo;

  Future<void> dispose() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await sync.dispose();
  }
}

Future<_Harness> _pumpActivity({
  required WidgetTester tester,
  required List<ActivityOfferSortRow> pinnedRows,
  required List<Map<String, dynamic>> streamWireItems,
  Size logicalSize = const Size(375, 667),
  Locale locale = const Locale('ru'),
  String? pendingInviteId,
}) async {
  final remote = _FixtureRemoteClient()..feedData = _feedData(streamWireItems);
  final fetched = await AttentionRepository(
    remote,
  ).fetch(view: AttentionView.all);
  final attentionRepo = Issue928AttentionRepo(fetched.page.items);

  final inboxRepo = FakeInboxRepository();
  final items = [for (final _ in pinnedRows) _requestInboxItem()];
  for (final item in items) {
    inboxRepo.inboxItemsByBeacon[item.beaconId] = item;
  }
  wireActivityOffersV2(
    inbox: inboxRepo,
    attention: attentionRepo,
    items: items,
    totalCount: pinnedRows.length,
  );
  attentionRepo.offerRows = pinnedRows;

  inboxRepo.inboxItemsByBeacon[_postId] = _legacyOpenPostInboxRow();

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('issue-928-test'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
    realtimeSyncCase: sync.case_,
  );
  accounts.emit('viewer');
  final invitePort = FakeAuthorInvitePort();
  if (pendingInviteId != null) {
    invitePort.pending = [
      PendingAuthorInvite(
        id: pendingInviteId,
        beaconId: _requestId,
        beaconTitle: _requestTitle,
        inviterId: 'alice',
        createdAt: DateTime.utc(2026, 10, 24),
      ),
    ];
  }
  final offers = ActivityOffersCubit(
    userId: 'viewer',
    inboxCase: inboxCase,
    attentionCase: attention,
    authorInviteCase: buildAuthorInviteCase(invitePort),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('issue-928-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await stream.stream.firstWhere((state) => state.firstLoadDone);

  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  ensureNoopAttentionActorProfilesRegistered();
  if (GetIt.I.isRegistered<RootRouter>()) GetIt.I.unregister<RootRouter>();
  GetIt.I.registerSingleton<RootRouter>(MockRootRouter());

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: offers),
          BlocProvider<UpdatesFeedCubit>.value(value: stream),
          BlocProvider<InboxCubit>.value(
            value: _TestInboxCubit(
              const InboxState(projectionLoaded: true),
            ),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: logicalSize),
            child: const TenturaResponsiveScope(
              child: Scaffold(body: ActivityStreamView()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final harness = _Harness(
    offers: offers,
    stream: stream,
    attention: attention,
    sync: sync.port,
    inboxRepo: inboxRepo,
    attentionRepo: attentionRepo,
  );
  addTearDown(harness.dispose);
  return harness;
}

void main() {
  test('ActivityOffersV2 scoped to a Post returns no pinned row', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'ActivityOffersV2': {
          '__typename': 'query_root',
          'activityOffers': {
            '__typename': 'ActivityOfferPage',
            'totalCount': 0,
            'nextCursor': null,
            'items': <Object?>[],
          },
        },
      },
      sent,
      (remote) async {
        final page = await AttentionRepository(
          remote,
        ).activityOffers(limit: 1, beaconId: _postId);
        expect(page.items, isEmpty);
      },
    );
    expect(sent.single.operationName, 'ActivityOffersV2');
    expect(sent.single.variables['beaconId'], _postId);
  });

  group('live room_message hint on a Post', () {
    Future<void> exercisePostHint(
      WidgetTester tester, {
      required ActivityOfferSortRow? pinnedInviteRow,
      Size size = kPhoneSurface,
    }) async {
      if (size == kPhoneSurface) {
        await usePhoneSurface(tester);
      }
      final harness = await _pumpActivity(
        tester: tester,
        pinnedRows: pinnedInviteRow == null ? const [] : [pinnedInviteRow],
        streamWireItems: [
          _groupWire(
            beaconId: _postId,
            beaconKind: 1,
            postRootExcerpt: 'Посоветуйте стоматолога в центре',
            events: [_arrivalEvent('Epost0000001')],
          ),
        ],
        logicalSize: size,
        pendingInviteId: pinnedInviteRow?.inviteId,
      );

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(
        harness.offers.state.items.map((e) => e.beaconId),
        pinnedInviteRow == null ? isEmpty : [_requestId],
      );

      harness.sync.emitChange(_roomMessageHint(_postId));
      await _settleDesk(tester);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(
        harness.offers.state.items.map((e) => e.beaconId),
        isNot(contains(_postId)),
      );
      if (pinnedInviteRow != null) {
        expect(harness.offers.state.items.map((e) => e.beaconId), [_requestId]);
      }
      if (pinnedInviteRow == null) {
        expect(find.text('Предложить помощь'), findsNothing);
        expect(find.text('Переслать'), findsNothing);
        expect(find.byType(RequestAttentionCard), findsNothing);
      } else if (pinnedInviteRow.inviteId != null) {
        expect(find.byType(ActivityInviteCard), findsOneWidget);
        expect(find.byType(RequestAttentionCard), findsNothing);
      } else {
        expect(find.byType(RequestAttentionCard), findsOneWidget);
      }
      expect(harness.attentionRepo.beaconOfferLookups, contains(_postId));
      expect(tester.takeException(), isNull);
    }

    testWidgets('pending author invite to child Request (375×667 RU)', (
      tester,
    ) async {
      await exercisePostHint(
        tester,
        pinnedInviteRow: _requestOfferRow(inviteId: 'Ipending001'),
      );
    });

    testWidgets('declined author invite to child Request (375×667 RU)', (
      tester,
    ) async {
      await exercisePostHint(
        tester,
        pinnedInviteRow: _requestOfferRow(declinedInvite: true),
      );
    });

    testWidgets('no pinned Request (desktop width)', (tester) async {
      await exercisePostHint(
        tester,
        pinnedInviteRow: null,
        size: const Size(1280, 800),
      );
    });
  });

  testWidgets('a live hint for an eligible Request still refreshes its card', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final harness = await _pumpActivity(
      tester: tester,
      pinnedRows: [_requestOfferRow()],
      streamWireItems: const [],
    );

    final closedItem = _requestInboxItem(status: BeaconStatus.closed);
    harness.inboxRepo.inboxItemsByBeacon[_requestId] = closedItem;
    harness.attentionRepo.offerRows = [
      activityOfferSortRow(closedItem),
    ];

    harness.sync.emitChange(_roomMessageHint(_requestId));
    await _settleDesk(tester);

    expect(harness.offers.state.items.single.beaconId, _requestId);
    expect(
      harness.offers.state.items.single.beacon?.status,
      BeaconStatus.closed,
    );
    expect(find.text('Предложить помощь'), findsNothing);
    expect(find.text('Статус: Закрыт'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _receiptWire({
  required String id,
  required String kind,
  required String itemKind,
  required String beaconId,
  int? beaconKind,
  String? postRootExcerpt,
  List<Map<String, dynamic>> events = const [],
}) => {
  '__typename': 'AttentionReceipt',
  'id': id,
  'category': 'requestProgress',
  'kind': kind,
  'priority': 'normal',
  'title': 'Заголовок',
  'body': 'Текст',
  'actionUrl': '/#/',
  'createdAt': '2026-09-10T12:00:00.000Z',
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': beaconId,
  'coordinationItemId': null,
  'actorUserId': 'Umaria0000001',
  'sourceEventKey': null,
  'destinationKind': 'beacon',
  'targetEntityId': beaconId,
  'presentationKey': null,
  'presentationPayloadJson': '{}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'surface': 'activity',
  'itemKind': itemKind,
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': events.length,
  'eventUnseenCount': events.length,
  'provenanceJson': null,
  'beaconAuthorId': 'Uanna00000001',
  'beaconAuthorName': 'Анна',
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': false,
  'beaconTitle': 'Пост',
  'beaconKind': beaconKind,
  'postRootExcerpt': postRootExcerpt,
  'postRootImageId': null,
  'eventsPreview': events,
};

Map<String, dynamic> _eventWire(String id, {required String kind}) =>
    _receiptWire(
      id: id,
      kind: kind,
      itemKind: 'receipt',
      beaconId: _postId,
    );

Map<String, dynamic> _arrivalEvent(String id) =>
    _eventWire(id, kind: 'newRelay');

Map<String, dynamic> _groupWire({
  required String beaconId,
  required int beaconKind,
  String? postRootExcerpt,
  List<Map<String, dynamic>> events = const [],
}) => _receiptWire(
  id: 'group-$beaconId',
  kind: 'roomActivityLowPriority',
  itemKind: 'requestActivity',
  beaconId: beaconId,
  beaconKind: beaconKind,
  postRootExcerpt: postRootExcerpt,
  events: [
    for (final event in events)
      {
        ...event,
        'beaconId': beaconId,
        'targetEntityId': beaconId,
        'beaconKind': beaconKind,
      },
  ],
);

GAttentionFeedData _feedData(List<Map<String, dynamic>> items) =>
    GAttentionFeedData.fromJson({
      '__typename': 'query_root',
      'attentionFeed': {
        '__typename': 'AttentionFeed',
        'summary': {
          '__typename': 'AttentionSummary',
          'unreadTotal': items.length,
          'needsYouTotal': 0,
        },
        'page': {
          '__typename': 'AttentionPage',
          'nextCursor': null,
          'items': items,
        },
      },
    })!;

final class _FixtureRemoteClient implements RemoteRequestClient {
  GAttentionFeedData? feedData;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    if (request is GAttentionFeedReq) {
      return Stream.value(
        OperationResponse<TData, TVars>(
          operationRequest: request,
          dataSource: DataSource.Link,
          data: feedData as TData,
        ),
      );
    }
    throw UnsupportedError('Unexpected operation: $request');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockRootRouter extends Mock implements RootRouter {}
