import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_offer_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../inbox/activity_offers_test_support.dart';
import '../inbox/inbox_case_test.dart'
    show
        FakeInboxRepository,
        buildTestBeaconThreadsCase,
        buildTestInboxCase;
import '../my_work/my_work_test_support.dart' hide buildTestBeaconThreadsCase;
import '../updates/support/noop_invite_setup_port.dart';

const _accountId = 'first-paint-user';
const _beaconTop = 'beacon-first-paint';
const _offerBeacon = 'beacon-offer-first';
const _kLeakTitle = 'LEAKED_IN_SCOPE_RECEIPT';
const _kActivityStreamTitle = 'Mutual connection formed';

const _viewport = Size(360, 640);
const _textScale = 1.3;

class _HarnessRouter extends Mock implements StackRouter {}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initial);


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
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => ProfileState(
    profile: Profile(id: _accountId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
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

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _FakeOrientationPrefs implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<void> setActivated({required String userId}) async {}

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<void> setOrientationDismissed({required String userId}) async {}

  @override
  Future<void> resetFirstRunState({required String userId}) async {}

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {}
}

class _PurityAttentionRepo extends ConfigurableActivityOffersAttentionRepo {
  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    if (surface == AttentionSurface.activity) {
      return AttentionFeed(
        summary: const AttentionSummary(),
        page: AttentionFeedPage(
          items: [
            AttentionReceipt(
              id: 'activity-only',
              category: 'social',
              kind: 'mutualConnectionFormed',
              priority: 'normal',
              title: _kActivityStreamTitle,
              body: 'Body',
              actionUrl: '/#/',
              createdAt: DateTime.utc(2026, 9, 10),
              collapsedCount: 1,
              presentationPayloadJson: '{}',
              surface: AttentionSurface.activity,
            ),
          ],
        ),
      );
    }
    if (view == AttentionView.needsYou) {
      return AttentionFeed(
        summary: const AttentionSummary(needsYouTotal: 1),
        page: AttentionFeedPage(
          items: [
            AttentionReceipt(
              id: 'obligation-row',
              category: 'asksOfMe',
              kind: 'needsMe',
              priority: 'normal',
              title: 'Standalone obligation receipt',
              body: 'Body',
              actionUrl: '/#/',
              createdAt: DateTime.utc(2026, 9, 10),
              collapsedCount: 1,
              presentationPayloadJson: '{}',
              surface: AttentionSurface.myWork,
              beaconId: _beaconTop,
              requiresAction: true,
            ),
          ],
        ),
      );
    }
    return const AttentionFeed(
      summary: AttentionSummary(),
      page: AttentionFeedPage(),
    );
  }

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

InboxItem _offerItem() {
  final at = DateTime.utc(2026, 6, 20);
  return InboxItem(
    beaconId: _offerBeacon,
    latestForwardAt: at,
    status: InboxItemStatus.needsMe,
    beacon: Beacon(
      id: _offerBeacon,
      title: 'First offer card',
      author: const Profile(id: 'a', displayName: 'Anna'),
      createdAt: at,
      updatedAt: at,
    ),
  );
}

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Future<void> _pumpMyWorkShell(WidgetTester tester) async {
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('work-activity-first-paint'));
  }
  if (!GetIt.I.isRegistered<BeaconRepository>()) {
    GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
  }
  if (!GetIt.I.isRegistered<EvaluationRepository>()) {
    GetIt.I.registerSingleton<EvaluationRepository>(
      EvaluationRepositoryMock(),
    );
  }
  final attentionRepo = _PurityAttentionRepo();
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('work-activity-first-paint'),
  );
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  accounts.emit(_accountId);
  await _drain();

  final myWorkRepo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [
        Beacon.empty.copyWith(
          id: _beaconTop,
          title: 'Top responsibility card',
          updatedAt: DateTime.utc(2026, 9, 5),
          status: BeaconStatus.open,
        ),
      ],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );

  final cubit = MyWorkCubit(
    userId: _accountId,
    myWorkCase: buildTestMyWorkCase(
      repo: myWorkRepo,
      attentionCase: attention,
    ),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('work-activity-first-paint'),
  );
  final homeActivation = HomeActivationCubit(_FakeOrientationPrefs());
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: 1,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );

  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: _viewport,
        textScaler: TextScaler.linear(_textScale),
      ),
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<MyWorkCubit>.value(value: cubit),
              BlocProvider<HomeActivationCubit>.value(value: homeActivation),
              BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
              BlocProvider<InboxOperationalCubit>.value(value: inboxOperational),
              BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
              BlocProvider(create: (_) => ScreenCubit.local()),
            ],
            child: const MyWorkScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 24 && !cubit.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpActivityShell(WidgetTester tester) async {
  final attentionRepo = _PurityAttentionRepo();
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('work-activity-first-paint-inbox'),
  );
  accounts.emit(_accountId);
  await _drain();

  final inboxRepo = FakeInboxRepository();
  final offer = _offerItem();
  wireActivityOffersV2(
    inbox: inboxRepo,
    attention: attentionRepo,
    items: [offer],
    totalCount: 1,
  );
  attentionRepo.offerRows = [
    activityOfferSortRow(
      offer,
      eventTotal: 1,
      eventsPreview: [
        AttentionReceipt(
          id: 'offer-event',
          category: 'requestProgress',
          kind: 'requestStatusChanged',
          priority: 'normal',
          title: 'Status changed',
          body: 'Body',
          actionUrl: '/#/',
          createdAt: DateTime.utc(2026, 6, 19),
          collapsedCount: 1,
          presentationPayloadJson: '{}',
          surface: AttentionSurface.activity,
          beaconId: _offerBeacon,
        ),
      ],
    ),
  ];
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  GetIt.I.registerSingleton<InboxCase>(inboxCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('work-activity-first-paint'));
  }

  final inboxCubit = _TestInboxCubit(
    const InboxState(status: StateIsSuccess(), projectionLoaded: true),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('work-activity-first-paint-inbox'),
  );

  await tester.binding.setSurfaceSize(_viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<InboxCubit>.value(value: inboxCubit),
          BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
          BlocProvider(create: (_) => HomeTabReselectCubit()),
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: _viewport,
              textScaler: TextScaler.linear(_textScale),
            ),
            child: const TenturaResponsiveScope(child: InboxScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 48; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await attention.refresh(
    destinationId: AttentionFeedDestinationId.activityStream,
  );
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.unregister<BeaconRepository>();
    }
    if (GetIt.I.isRegistered<EvaluationRepository>()) {
      GetIt.I.unregister<EvaluationRepository>();
    }
    if (GetIt.I.isRegistered<AttentionCase>()) {
      final attention = GetIt.I<AttentionCase>();
      unawaited(attention.dispose());
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InboxCase>()) {
      GetIt.I.unregister<InboxCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<Logger>()) {
      GetIt.I.unregister<Logger>();
    }
  });

  testWidgets('My Work shell: first card visible, no obligations pane (§9)',
      (tester) async {
    await _pumpMyWorkShell(tester);

    final cardFinder = find.byType(MyWorkCardRouter);
    expect(cardFinder, findsWidgets);
    final rect = tester.getRect(cardFinder.first);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(_viewport.height));
    expect(find.byType(UpdatesFeedTile), findsNothing);
    expect(find.text('Standalone obligation receipt'), findsNothing);
  });

  testWidgets('Activity shell: first offer card visible on first paint (§9)',
      (tester) async {
    await _pumpActivityShell(tester);

    final offerFinder = find.bySemanticsIdentifier(
      TestIds.activityOffer(_offerBeacon),
    );
    expect(offerFinder, findsOneWidget);
    final rect = tester.getRect(offerFinder);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(_viewport.height));
    expect(find.byType(ActivityOfferCard), findsOneWidget);
  });

  testWidgets('Activity shell: no in-scope myWork receipt rows (§9.1)',
      (tester) async {
    await _pumpActivityShell(tester);

    expect(find.text(_kActivityStreamTitle), findsOneWidget);
    expect(find.text('Standalone obligation receipt'), findsNothing);
    expect(find.text(_kLeakTitle), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is UpdatesFeedTile &&
            w.receipt.surface == AttentionSurface.myWork,
      ),
      findsNothing,
    );
  });
}
