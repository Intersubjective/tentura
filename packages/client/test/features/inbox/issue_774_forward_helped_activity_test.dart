// #774 r3: forwardHelped «вам» row on Activity Request cards + help path wrap.

import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/forward_helped_see_path_action.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
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

/// Matches the server `ForwardHelpedContent.toPayload` shape.
Map<String, Object?> _forwardHelpedPayload({
  required String viewerUserId,
  required String viewerName,
  bool done = false,
  int collapsedHelpers = 1,
}) {
  return {
    'eventType': 'forwardHelped',
    'beaconId': _beaconId,
    'beaconTitle': _title,
    'authorId': _annaId,
    'helperId': _veraId,
    'done': done,
    'path': [
      {'userId': _annaId, 'displayName': 'Anna', 'anonymousCount': 0},
      {'userId': _borisId, 'displayName': 'Boris', 'anonymousCount': 0},
      {'userId': _kiraId, 'displayName': 'Kira', 'anonymousCount': 0},
      {
        'userId': viewerUserId,
        'displayName': viewerName,
        'anonymousCount': 0,
      },
      {'userId': _veraId, 'displayName': 'Vera', 'anonymousCount': 0},
    ],
    if (collapsedHelpers > 1) 'collapsedHelpers': collapsedHelpers,
  };
}

AttentionReceipt _forwardHelpedEvent({
  required String viewerUserId,
  String viewerName = 'Kim',
  bool done = false,
  int collapsedCount = 1,
  String id = 'r-forward-helped',
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  title: done ? 'Your forward helped · Done ✓' : 'Your forward helped',
  body: '',
  actionUrl: '/#/view/$_beaconId',
  createdAt: DateTime.utc(2026, 11, 8, 12),
  collapsedCount: collapsedCount,
  presentationKey: 'forward_helped',
  presentationPayloadJson: jsonEncode(
    _forwardHelpedPayload(
      viewerUserId: viewerUserId,
      viewerName: viewerName,
      done: done,
    ),
  ),
  surface: AttentionSurface.activity,
  beaconId: _beaconId,
  beaconTitle: _title,
  targetEntityId: _veraId,
);

AttentionReceipt _requestActivityCard({
  required List<AttentionReceipt> eventsPreview,
}) => AttentionReceipt(
  id: 'activity-$_beaconId',
  category: 'requestProgress',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: _title,
  body: '',
  actionUrl: '/#/view/$_beaconId',
  createdAt: DateTime.utc(2026, 11, 8, 11),
  collapsedCount: 0,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.requestActivity,
  beaconId: _beaconId,
  beaconAuthorId: _annaId,
  beaconAuthorName: 'Anna',
  eventTotal: eventsPreview.length,
  eventUnseenCount: eventsPreview.length,
  eventsPreview: eventsPreview,
);

class _ClearSpyRepo extends AttentionRepositoryFake {
  _ClearSpyRepo(this.feed);

  final List<AttentionReceipt> feed;
  final cleared = <String>[];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: const AttentionSummary(unreadTotal: 1),
    page: AttentionFeedPage(items: feed),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async => AttentionClearSnapshot(
    snapshotToken: 'token-$receiptId',
    receiptIds: [?receiptId],
  );

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async {
    final id = snapshotToken.replaceFirst('token-', '');
    cleared.add(id);
    return AttentionClearResult(
      operationId: operationId,
      status: AttentionOperationStatus.complete,
      appliedReceiptIds: [id],
    );
  }

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

class _StreamFeedRepo extends ConfigurableActivityOffersAttentionRepo {
  _StreamFeedRepo(this.firstPage);

  final List<AttentionReceipt> firstPage;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => AttentionFeed(
    summary: const AttentionSummary(unreadTotal: 1),
    page: AttentionFeedPage(items: firstPage),
  );
}

Future<void> _pumpActivityStream(
  WidgetTester tester, {
  required List<AttentionReceipt> streamPage,
  required String viewerUserId,
  Size logicalSize = kPhoneSurface,
  Locale locale = const Locale('ru'),
  double textScale = 2,
}) async {
  await usePhoneSurface2x(tester);
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);

  final inboxRepo = FakeInboxRepository();
  final attentionRepo = _StreamFeedRepo(streamPage);
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('issue-774-activity'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
  );
  accounts.emit(viewerUserId);
  ensureNoopAttentionActorProfilesRegistered();
  final offers = ActivityOffersCubit(
    userId: viewerUserId,
    inboxCase: inboxCase,
    attentionCase: attention,
    actorProfiles: buildNoopAttentionActorProfiles(),
    effects: FakeUiEffectPort(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('issue-774-activity'),
  );
  await attention.refresh();

  if (GetIt.I.isRegistered<AttentionCase>()) {
    await GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  if (GetIt.I.isRegistered<ProfileCubit>()) {
    await GetIt.I.unregister<ProfileCubit>();
  }
  GetIt.I.registerSingleton<ProfileCubit>(_FakeProfileCubit(viewerUserId));
  if (!GetIt.I.isRegistered<AppNavigator>()) {
    registerFakeAppNavigator();
  }
  addTearDown(() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await accounts.close();
    if (GetIt.I.isRegistered<AttentionCase>()) {
      await GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<ProfileCubit>()) {
      await GetIt.I.unregister<ProfileCubit>();
    }
  });

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: offers),
          BlocProvider<UpdatesFeedCubit>.value(value: stream),
          BlocProvider<InboxCubit>.value(value: _TestInboxCubit()),
        ],
        child: MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              textScaler: TextScaler.linear(textScale),
            ),
            child: BlocProvider<ScreenCubit>.value(
              value: ScreenCubit(FakeUiEffectPort()),
              child: const TenturaResponsiveScope(
                child: Scaffold(body: ActivityStreamView()),
              ),
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
}

Widget _cardHost({
  required String viewerUserId,
  required List<AttentionReceipt> events,
  void Function(String id)? onClear,
}) => _CardHost(
  viewerUserId: viewerUserId,
  events: events,
  onClear: onClear,
);

class _CardHost extends StatefulWidget {
  const _CardHost({
    required this.viewerUserId,
    required this.events,
    this.onClear,
  });

  final String viewerUserId;
  final List<AttentionReceipt> events;
  final void Function(String id)? onClear;

  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  late List<AttentionReceipt> _events = widget.events;

  @override
  Widget build(BuildContext context) {
    return RequestAttentionCard(
      beacon: Beacon(
        id: _beaconId,
        title: _title,
        createdAt: DateTime.utc(2026, 11),
        updatedAt: DateTime.utc(2026, 11, 8),
        author: const Profile(id: _annaId, displayName: 'Anna'),
      ),
      facts: const RequestAttentionFacts(requestId: _beaconId),
      eventsPreview: _events,
      eventTotal: _events.length,
      viewerUserId: widget.viewerUserId,
      onOpenBeacon: () {},
      onOpenTimeline: () {},
      onClearEvent: (id) {
        widget.onClear?.call(id);
        setState(
          () => _events = _events
              .where((e) => e.id != id)
              .toList(growable: false),
        );
      },
    );
  }
}

Future<void> _pumpCard(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('ru'),
  Size size = kPhoneSurface,
}) async {
  await usePhoneSurface2x(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: const TextScaler.linear(2),
        ),
        child: BlocProvider<ScreenCubit>.value(
          value: ScreenCubit(FakeUiEffectPort()),
          child: TenturaResponsiveScope(child: Scaffold(body: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Activity stream: Kira sees forwardHelped row with Вы, ×, Field',
    (tester) async {
      final event = _forwardHelpedEvent(
        viewerUserId: _kiraId,
        viewerName: 'Kira',
      );
      await _pumpActivityStream(
        tester,
        streamPage: [
          _requestActivityCard(eventsPreview: [event]),
        ],
        viewerUserId: _kiraId,
      );

      expect(find.byType(RequestAttentionCard), findsOneWidget);
      expect(find.textContaining('Ваша пересылка помогла'), findsOneWidget);
      expect(find.textContaining('Вы'), findsWidgets);
      expect(find.text('Показать на поле ›'), findsOneWidget);
      expect(find.byKey(AttentionMiniCard.dismissKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Activity stream: Boris (first hop) sees You at 1280 EN', (
    tester,
  ) async {
    final event = _forwardHelpedEvent(
      viewerUserId: _borisId,
      viewerName: 'Boris',
    );
    await _pumpActivityStream(
      tester,
      streamPage: [
        _requestActivityCard(eventsPreview: [event]),
      ],
      viewerUserId: _borisId,
      logicalSize: const Size(1280, 800),
      locale: const Locale('en'),
      textScale: 1,
    );

    expect(find.textContaining('Your forward helped'), findsOneWidget);
    expect(find.textContaining('You'), findsWidgets);
    expect(find.text('Show on Field ›'), findsOneWidget);
    expect(find.byKey(AttentionMiniCard.dismissKey), findsOneWidget);
  });

  testWidgets('card × clears forwardHelped and row leaves', (tester) async {
    String? clearedId;
    await _pumpCard(
      tester,
      _cardHost(
        viewerUserId: _kiraId,
        events: [_forwardHelpedEvent(viewerUserId: _kiraId)],
        onClear: (id) => clearedId = id,
      ),
    );

    final dismiss = find.byKey(AttentionMiniCard.dismissKey);
    expect(dismiss, findsOneWidget);
    await tester.tap(dismiss);
    await tester.pumpAndSettle();
    expect(clearedId, 'r-forward-helped');
    expect(find.textContaining('Ваша пересылка помогла'), findsNothing);
  });

  testWidgets('closed card keeps forwardHelped row with ×', (tester) async {
    final done = _forwardHelpedEvent(
      viewerUserId: _kiraId,
      done: true,
    );
    await _pumpCard(
      tester,
      RequestAttentionCard(
        beacon: Beacon(
          id: _beaconId,
          title: _title,
          createdAt: DateTime.utc(2026, 11),
          updatedAt: DateTime.utc(2026, 11, 8),
          status: BeaconStatus.closed,
          author: const Profile(id: _annaId, displayName: 'Anna'),
        ),
        facts: const RequestAttentionFacts(requestId: _beaconId),
        eventsPreview: [done],
        eventTotal: 1,
        viewerUserId: _kiraId,
        onOpenBeacon: () {},
        onOpenTimeline: () {},
        onClearEvent: (_) {},
      ),
    );

    expect(find.textContaining('Готово ✓'), findsWidgets);
    expect(find.byKey(AttentionMiniCard.dismissKey), findsOneWidget);
    expect(find.byType(ForwardHelpedSeePathAction), findsOneWidget);
  });

  testWidgets('plural collapsedCount shows two people copy', (tester) async {
    await _pumpCard(
      tester,
      _cardHost(
        viewerUserId: _kiraId,
        events: [
          _forwardHelpedEvent(viewerUserId: _kiraId, collapsedCount: 2),
        ],
      ),
      locale: const Locale('en'),
    );

    expect(find.textContaining('2 people'), findsOneWidget);
  });

  testWidgets('card without forwardHelped preview has no × row', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      _cardHost(
        viewerUserId: _kiraId,
        events: [
          AttentionReceipt(
            id: 'status-only',
            category: 'requestProgress',
            kind: 'roomActivityLowPriority',
            priority: 'normal',
            title: _title,
            body: '',
            actionUrl: '/#/',
            createdAt: DateTime.utc(2026, 11, 8),
            collapsedCount: 1,
            presentationPayloadJson:
                '{"eventType":"requestStatusChanged","personal":false}',
            presentationKey: 'request_status_changed',
            surface: AttentionSurface.activity,
            beaconId: _beaconId,
          ),
        ],
      ),
    );

    expect(find.byKey(AttentionMiniCard.dismissKey), findsNothing);
    expect(find.text('Показать на поле ›'), findsNothing);
  });

  testWidgets('Activity × reaches clearReceipt', (tester) async {
    final event = _forwardHelpedEvent(viewerUserId: _kiraId);
    final feed = [
      _requestActivityCard(eventsPreview: [event]),
    ];
    final repo = _ClearSpyRepo(feed);
    final accounts = _Accounts();
    final sync = buildTestRealtimeSync();
    final attention = AttentionCase(
      repo,
      accounts,
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('issue-774-clear'),
    );
    GetIt.I.registerSingleton<AttentionCase>(attention);
    GetIt.I.registerSingleton<ProfileCubit>(_FakeProfileCubit(_kiraId));
    registerFakeAppNavigator();
    addTearDown(() async {
      await attention.dispose();
      await accounts.close();
      await GetIt.I.reset();
    });

    await _pumpCard(
      tester,
      RequestAttentionCard(
        beacon: Beacon(
          id: _beaconId,
          title: _title,
          createdAt: DateTime.utc(2026, 11),
          updatedAt: DateTime.utc(2026, 11, 8),
          author: const Profile(id: _annaId, displayName: 'Anna'),
        ),
        facts: const RequestAttentionFacts(requestId: _beaconId),
        eventsPreview: [event],
        eventTotal: 1,
        viewerUserId: _kiraId,
        onOpenBeacon: () {},
        onOpenTimeline: () {},
        onClearEvent: (id) => unawaited(
          GetIt.I<AttentionCase>().clearReceipt(receiptId: id),
        ),
      ),
    );

    await tester.tap(find.byKey(AttentionMiniCard.dismissButtonKey));
    await tester.pumpAndSettle();
    expect(repo.cleared, ['r-forward-helped']);
  });
}
