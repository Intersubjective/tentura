// A Post (a beacon of kind 1) that reaches «Для вас» is drawn as a light
// `PostAttentionRow`, not as a `RequestAttentionCard`. These tests run the
// whole path: a GraphQL response in the shape of the shared receipt fragment
// → `AttentionRepository.fetch` → the For You stream → the row on screen.

import 'dart:async';

import 'package:ferry/ferry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.data.gql.dart';
import 'package:tentura/features/attention/data/gql/_g/attention_feed.req.gql.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

const _postId = 'Bpost000000001';
const _requestId = 'Brequest00001';
const _rootImageId = 'Iroot00000001';

void main() {
  group('attention receipt wire mapping of Post fields', () {
    final remote = _FixtureRemoteClient();
    final repository = AttentionRepository(remote);

    tearDown(() => remote.feedData = null);

    test('a Post group keeps its kind, root excerpt and root image id',
        () async {
      remote.feedData = _feedData([
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Посоветуйте стоматолога в центре',
          postRootImageId: _rootImageId,
        ),
      ]);

      final receipt = (await repository.fetch(view: AttentionView.all))
          .page
          .items
          .single;

      expect(receipt.beaconKind, 1);
      expect(receipt.postRootExcerpt, 'Посоветуйте стоматолога в центре');
      expect(receipt.postRootImageId, _rootImageId);
    });

    test('a Request group keeps kind 0 and carries no Post root', () async {
      remote.feedData = _feedData([
        _groupWire(beaconId: _requestId, beaconKind: 0),
      ]);

      final receipt = (await repository.fetch(view: AttentionView.all))
          .page
          .items
          .single;

      expect(receipt.beaconKind, 0);
      expect(receipt.postRootExcerpt, isNull);
      expect(receipt.postRootImageId, isNull);
    });

    test('a Post root without a photo has no image id', () async {
      remote.feedData = _feedData([
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Без фото',
        ),
      ]);

      final receipt = (await repository.fetch(view: AttentionView.all))
          .page
          .items
          .single;

      expect(receipt.beaconKind, 1);
      expect(receipt.postRootExcerpt, 'Без фото');
      expect(receipt.postRootImageId, isNull);
    });
  });

  group('For You stream row for a Post group', () {
    testWidgets('an arrival is a Post row with the root excerpt and the '
        'forward note, not a Request card', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Посоветуйте стоматолога в центре',
          provenanceJson: _forwardProvenance,
          events: [_arrivalEvent('Eevent000001')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(find.byType(RequestAttentionCard), findsNothing);
      expect(find.byType(UpdatesFeedTile), findsNothing);

      expect(find.textContaining('Анна'), findsWidgets);
      expect(find.textContaining('поделил'), findsOneWidget);
      expect(
        find.textContaining('Посоветуйте стоматолога в центре'),
        findsOneWidget,
      );
      expect(find.textContaining('ты же спрашивал недавно'), findsOneWidget);
      expect(find.textContaining('Илья'), findsWidgets);
    });

    testWidgets('an arrival whose root has a photo shows that photo as a '
        'thumbnail', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Смотрите, какой кот у нас поселился',
          postRootImageId: _rootImageId,
          provenanceJson: _forwardProvenance,
          events: [_arrivalEvent('Eevent000009')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(_rootThumbnail(), findsOneWidget);
    });

    testWidgets('an arrival whose root has no photo shows no thumbnail',
        (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Посоветуйте стоматолога в центре',
          provenanceJson: _forwardProvenance,
          events: [_arrivalEvent('Eevent000010')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(_rootThumbnail(), findsNothing);
    });

    testWidgets('a reply to the viewer says «вам ответили»', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Кто в субботу на велопрогулку?',
          events: [_replyEvent('Eevent000002')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(find.byType(RequestAttentionCard), findsNothing);
      expect(find.textContaining('вам ответили'), findsOneWidget);
      expect(find.textContaining('поделил'), findsNothing);
    });

    testWidgets('an @mention says «вас упомянули»', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Кто в субботу на велопрогулку?',
          events: [_mentionEvent('Eevent000003')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(find.textContaining('вас упомянули'), findsOneWidget);
      expect(find.textContaining('вам ответили'), findsNothing);
    });

    testWidgets("the first responses to the viewer's own Post say "
        '«На ваш пост откликнулись» above the root excerpt', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Смотрите, какой кот у нас поселился',
          events: [_firstResponseEvent('Eevent000004')],
        ),
      ]);

      expect(find.byType(PostAttentionRow), findsOneWidget);
      expect(find.textContaining('На ваш пост откликнулись'), findsOneWidget);
      expect(
        find.textContaining('Смотрите, какой кот у нас поселился'),
        findsOneWidget,
      );
    });

    testWidgets('a Request group still renders the Request card',
        (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _requestId,
          beaconKind: 0,
          events: [_arrivalEvent('Eevent000005')],
        ),
      ]);

      expect(find.byType(RequestAttentionCard), findsOneWidget);
      expect(find.byType(PostAttentionRow), findsNothing);
    });

    testWidgets('a Request and a Post group in one stream each get their '
        'own row', (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _requestId,
          beaconKind: 0,
          events: [_arrivalEvent('Eevent000006')],
        ),
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Отдам даром шкаф',
          events: [_replyEvent('Eevent000007')],
        ),
      ], logicalSize: const Size(400, 2000));

      expect(find.byType(RequestAttentionCard), findsOneWidget);
      expect(find.byType(PostAttentionRow), findsOneWidget);
    });

    testWidgets('tapping the row opens the Post at /beacon/view/<id>',
        (tester) async {
      final harness = await _pumpFeed(tester, [
        _groupWire(
          beaconId: _postId,
          beaconKind: 1,
          postRootExcerpt: 'Кто в субботу на велопрогулку?',
          events: [_replyEvent('Eevent000008')],
        ),
      ]);

      await tester.tap(find.byType(PostAttentionRow));
      await tester.pump();

      final opened = harness.router.opened.single;
      expect(opened.beaconId, _postId);
      expect(attentionDestination(opened).path, '$kPathBeaconView/$_postId');
    });
  });
}

/// The Post root's photo, drawn from the image server under its author.
Finder _rootThumbnail() => find.byWidgetPredicate((widget) {
  if (widget is! Image) return false;
  final provider = widget.image;
  return provider is NetworkImage &&
      provider.url.contains('Uanna00000001') &&
      provider.url.contains(_rootImageId);
});

const _forwardProvenance =
    '{"senders":[{"id":"sender-1","displayName":"Илья", '
    '"notePreview":"ты же спрашивал недавно","reasonSlugs":[],"mr":0.4}], '
    '"totalDistinctSenders":1, '
    '"strongestNotePreview":"ты же спрашивал недавно", '
    '"latestNoteForward":{"forwardId":"fw-1","senderId":"sender-1", '
    '"displayName":"Илья","notePreview":"ты же спрашивал недавно", '
    '"forwardedAt":"2026-09-10T09:00:00Z","reasonSlugs":[]}}';

/// One attention receipt in the JSON shape of the `AttentionReceiptFields`
/// fragment: the keys the server sends, including the Post columns.
Map<String, dynamic> _receiptWire({
  required String id,
  required String kind,
  required String itemKind,
  required String beaconId,
  int? beaconKind,
  String? postRootExcerpt,
  String? postRootImageId,
  String? provenanceJson,
  String presentationPayloadJson = '{}',
  int? eventTotal,
  int? eventUnseenCount,
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
  'presentationPayloadJson': presentationPayloadJson,
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
  'eventTotal': eventTotal,
  'eventUnseenCount': eventUnseenCount,
  'provenanceJson': provenanceJson,
  'beaconAuthorId': 'Uanna00000001',
  'beaconAuthorName': 'Анна',
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': false,
  'beaconTitle': 'Пост',
  'beaconKind': beaconKind,
  'postRootExcerpt': postRootExcerpt,
  'postRootImageId': postRootImageId,
  'eventsPreview': events,
};

/// One child event as production writes it: the GraphQL `kind` is the
/// `NotificationKind` name, and the event type the client classifies by is
/// `presentationPayloadJson.eventType` — the two are not the same string.
Map<String, dynamic> _eventWire(
  String id, {
  required String kind,
  required String eventType,
}) => _receiptWire(
  id: id,
  kind: kind,
  itemKind: 'receipt',
  beaconId: _postId,
  presentationPayloadJson: '{"eventType":"$eventType"}',
);

Map<String, dynamic> _arrivalEvent(String id) =>
    _eventWire(id, kind: 'newRelay', eventType: 'relayReceived');

Map<String, dynamic> _replyEvent(String id) => _eventWire(
  id,
  kind: 'roomActivityLowPriority',
  eventType: 'roomMessagePosted',
);

/// An `@handle` mention is the same event type as a reply; only the
/// notification kind differs.
Map<String, dynamic> _mentionEvent(String id) =>
    _eventWire(id, kind: 'roomMention', eventType: 'roomMessagePosted');

Map<String, dynamic> _firstResponseEvent(String id) => _eventWire(
  id,
  kind: 'postFirstResponse',
  eventType: 'postFirstResponse',
);

/// The grouped row the server synthesizes for a beacon with live events.
Map<String, dynamic> _groupWire({
  required String beaconId,
  required int beaconKind,
  String? postRootExcerpt,
  String? postRootImageId,
  String? provenanceJson,
  List<Map<String, dynamic>> events = const [],
}) => _receiptWire(
  id: 'group-$beaconId',
  kind: 'roomActivityLowPriority',
  itemKind: 'requestActivity',
  beaconId: beaconId,
  beaconKind: beaconKind,
  postRootExcerpt: postRootExcerpt,
  postRootImageId: postRootImageId,
  provenanceJson: provenanceJson,
  eventTotal: events.length,
  eventUnseenCount: events.length,
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

/// Serves the receipts the real repository mapped from the wire JSON.
class _MappedFeedRepo extends ConfigurableActivityOffersAttentionRepo {
  _MappedFeedRepo(this.items);

  final List<AttentionReceipt> items;

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
      items: cursor == null || cursor.isEmpty ? items : const [],
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

class _RecordingRootRouter extends Mock implements RootRouter {
  final opened = <AttentionReceipt>[];

  @override
  Future<void> openFromUpdate(AttentionReceipt receipt) async {
    opened.add(receipt);
  }
}

class _HarnessRouter extends Mock implements StackRouter {}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _Harness {
  _Harness({
    required this.offers,
    required this.stream,
    required this.attention,
    required this.accounts,
    required this.router,
  });

  final ActivityOffersCubit offers;
  final UpdatesFeedCubit stream;
  final AttentionCase attention;
  final _Accounts accounts;
  final _RecordingRootRouter router;

  Future<void> dispose() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await accounts.close();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<RootRouter>()) {
      GetIt.I.unregister<RootRouter>();
    }
  }
}

/// Runs [wireItems] through the real repository and pumps the For You stream
/// over the receipts it produced.
Future<_Harness> _pumpFeed(
  WidgetTester tester,
  List<Map<String, dynamic>> wireItems, {
  Size logicalSize = const Size(360, 800),
}) async {
  final remote = _FixtureRemoteClient()..feedData = _feedData(wireItems);
  final fetched = await AttentionRepository(
    remote,
  ).fetch(view: AttentionView.all);
  final attentionRepo = _MappedFeedRepo(fetched.page.items);

  final inboxRepo = FakeInboxRepository();
  wireActivityOffersV2(
    inbox: inboxRepo,
    attention: attentionRepo,
    items: const [],
    totalCount: 0,
  );

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('post-attention-row-test'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );
  accounts.emit('viewer');
  final offers = ActivityOffersCubit(
    userId: 'viewer',
    inboxCase: inboxCase,
    attentionCase: attention,
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('post-attention-row-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await attention.refresh();

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
  final router = _RecordingRootRouter();
  GetIt.I.registerSingleton<RootRouter>(router);

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
          locale: const Locale('ru'),
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
    accounts: accounts,
    router: router,
  );
  // Closing the cubits awaits stream cancellations that only complete outside
  // the test's fake-async zone, so it runs as a tearDown, not inline.
  addTearDown(harness.dispose);
  return harness;
}
