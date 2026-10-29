import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_repository_fake_base.dart';
import '../../support/test_realtime_sync.dart';
import '../../support/noop_posts_case.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../../support/noop_attention_actor_profiles.dart';

class _HarnessRouter extends Mock implements StackRouter {
  PageRouteInfo? lastPush;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    lastPush = route;
    return null;
  }
}

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
  Future<void> dismiss(String beaconId, {String note = ''}) async {}

  @override
  Future<void> reject(String beaconId, {String message = ''}) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  Future<void> dismissTombstone(String beaconId) async {}
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

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

/// Holds each primary source independently, including subsequent refreshes.
class _ControlledAttentionRepo extends AttentionRepositoryFake {
  Completer<ActivityOfferPage> offersResponse = Completer<ActivityOfferPage>();
  Completer<AttentionFeed> feedResponse = Completer<AttentionFeed>();
  int offerCalls = 0;
  int feedCalls = 0;

  @override
  Future<ActivityOfferPage> activityOffers({
    String? beaconId,
    String? cursor,
    int limit = 20,
  }) {
    offerCalls++;
    return offersResponse.future;
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) {
    feedCalls++;
    return feedResponse.future;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};
  @override
  Future<Set<String>> liveObligationBeacons() async => {};
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

Future<void> _pumpInbox(
  WidgetTester tester, {
  required _ControlledAttentionRepo attentionRepo,
  required _HarnessRouter router,
  _DelayedJoinedProfile? joinedProfile,
}) async {
  const logicalSize = Size(800, 800);
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  registerNoopPostsCase(sync.case_);
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-first-load-test'),
  );
  accounts.emit('viewer');
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final inboxRepo = FakeInboxRepository()
    ..openForwardsCount = 1
    ..inboxItemsByBeacon = {_offer.beaconId: _offer};
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
  );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  if (joinedProfile != null) {
    if (GetIt.I.isRegistered<AttentionActorProfilesCase>()) {
      await GetIt.I.unregister<AttentionActorProfilesCase>();
    }
    final actors = AttentionActorProfilesCase(joinedProfile, accounts);
    GetIt.I.registerSingleton<AttentionActorProfilesCase>(actors);
    addTearDown(() async {
      await GetIt.I.unregister<AttentionActorProfilesCase>();
      await actors.dispose();
    });
  } else {
    ensureNoopAttentionActorProfilesRegistered();
  }
  GetIt.I.registerSingleton(inboxCase);
  GetIt.I.registerSingleton<InviteAcceptedSetupPort>(
    joinedProfile ?? NoopInviteAcceptedSetupPort(),
  );
  GetIt.I.registerSingleton<RealtimeSyncCase>(sync.case_);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('activity-first-load-test'));
  }
  final inboxCubit = _TestInboxCubit(
    const InboxState(status: StateIsSuccess(), projectionLoaded: true),
  );
  final homeAttention = HomeAttentionCubit(
    attention,
    accounts,
    Logger('activity-first-load-test'),
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await inboxCubit.close();
    await homeAttention.close();
    await attention.dispose();
    await accounts.close();
    await sync.port.dispose();
    if (GetIt.I.isRegistered<AttentionCase>()) {
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

  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
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
            data: MediaQueryData(size: logicalSize),
            child: const TenturaResponsiveScope(child: InboxScreen()),
          ),
        ),
      ),
    ),
  );
  // Flush microtasks without advancing the gate clock.
  await tester.pump();
}

final _at = DateTime.utc(2026, 10, 28);
final _offer = InboxItem(
  beaconId: 'repair-request',
  latestForwardAt: _at,
  status: InboxItemStatus.needsMe,
  beacon: Beacon(
    id: 'repair-request',
    title: 'Repair the garden gate',
    author: const Profile(id: 'author', displayName: 'Anna'),
    createdAt: _at,
    updatedAt: _at,
  ),
);
final _receipt = AttentionReceipt(
  id: 'delivery-update',
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Delivery arranged for Friday',
  body: 'A neighbour has confirmed',
  actionUrl: '/#/',
  createdAt: _at,
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
);

void _finishOffers(_ControlledAttentionRepo repo) {
  repo.offersResponse.complete(
    ActivityOfferPage(
      items: [
        ActivityOfferSortRow(
          beaconId: _offer.beaconId,
          listPositionAt: _at,
          effectiveActivityAt: _at,
          latestForwardAt: _at,
          unseen: false,
          eventTotal: 0,
          eventUnseenCount: 0,
        ),
      ],
      totalCount: 1,
    ),
  );
}

void _finishFeed(_ControlledAttentionRepo repo) {
  repo.feedResponse.complete(
    AttentionFeed(
      summary: const AttentionSummary(),
      page: AttentionFeedPage(items: [_receipt]),
    ),
  );
}

Future<void> _frames(WidgetTester tester) async {
  // Well inside the gate's 2.5-second escape timeout.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

({int gateSpinners, int allSpinners, int offers, int updates})
_visibleFrame() => (
  gateSpinners: find
      .descendant(
        of: find.byType(TenturaFirstLoadGate),
        matching: find.byType(CircularProgressIndicator),
      )
      .evaluate()
      .length,
  allSpinners: find.byType(CircularProgressIndicator).evaluate().length,
  offers: find.text('Repair the garden gate').evaluate().length,
  updates: find.text('Delivery arranged for Friday').evaluate().length,
);

/// Both profile paths see the same delayed person, as they do over the real
/// profile repository. Prompt state is already available, isolating person I/O.
class _DelayedJoinedProfile
    implements InviteAcceptedSetupPort, ProfileRepositoryPort {
  final response = Completer<Profile>();
  final requestedIds = <String>[];

  static const person = Profile(id: 'joined-person', displayName: 'QA Bob');
  static const prompt = InviteSeedPromptState(
    inviterUserId: 'viewer',
    inviteeUserId: 'joined-person',
    state: PromptStateValue.pending,
  );

  @override
  Future<Profile> fetchProfile(String subjectId) {
    requestedIds.add(subjectId);
    return response.future;
  }

  @override
  Future<Profile> fetchById(String id) => fetchProfile(id);

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async {
    requestedIds.addAll(ids);
    final person = await response.future;
    return ids.contains(person.id) ? [person] : [];
  }

  @override
  Future<InviteSeedPromptState> fetchPrompt(String subjectId) async => prompt;

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async => {if (subjectIds.contains(person.id)) person.id: prompt};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Activity first load', () {
    testWidgets(
      'reveals a joined person in the final card layout without a placeholder name',
      (tester) async {
        final repo = _ControlledAttentionRepo();
        final profile = _DelayedJoinedProfile();
        final receipt = _receipt.copyWith(
          id: 'joined-receipt',
          category: 'connections',
          kind: 'inviteAccepted',
          title: 'New member',
          body: 'New member is now on Tentura.',
          actionUrl: '/profile/view/joined-person',
          presentationKey: 'invite_accepted',
          presentationPayloadJson: '{"inviteOrigin":"new_account"}',
          actorUserId: 'joined-person',
          targetEntityId: 'joined-person',
        );
        final card = find.byType(InviteAcceptedReceiptCard);
        final setupAction = find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (w) =>
                w is TenturaTextAction &&
                w.semanticsIdentifier == TestIds.inviteAcceptedSetupOpen,
          ),
        );
        // The gate's visible scroll content detects reveal independently of
        // the receipt's widget type: a flat tile must not escape observation.
        final visibleContent = find.descendant(
          of: find.byType(TenturaFirstLoadGate),
          matching: find.byType(CustomScrollView),
        );
        // Resolving the prompt behind the gate may place this receipt in
        // the pinned zone, which has a different key and card shell.
        final item = card;
        double? firstVisibleHeight;

        void captureFrame() {
          // Check every frame, even when no InviteAcceptedReceiptCard exists.
          expect(
            find.textContaining('New member'),
            findsNothing,
            reason:
                'Activity must never expose the receipt placeholder, '
                'including in a flat row before the card appears',
          );
          final gate = tester.widget<TenturaFirstLoadGate>(
            find.byType(TenturaFirstLoadGate),
          );
          final gateVisibility = tester.widget<Visibility>(
            find.descendant(
              of: find.byType(TenturaFirstLoadGate),
              matching: find.byWidgetPredicate(
                (w) => w is Visibility && identical(w.child, gate.child),
                skipOffstage: false,
              ),
              skipOffstage: false,
            ),
          );
          final revealed =
              gateVisibility.visible &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty &&
              visibleContent.hitTestable().evaluate().isNotEmpty;
          if (firstVisibleHeight != null || !revealed) return;
          // Assert immediately on the first revealed frame. If the gate
          // opens while the profile is pending, these checks run before we
          // release it. If it waits, they run on the first frame after release.
          expect(
            item,
            findsOneWidget,
            reason: 'The first revealed Activity frame must contain the item',
          );
          expect(
            card,
            findsOneWidget,
            reason: 'The first revealed item must already use the card layout',
          );
          expect(
            find.descendant(of: item, matching: find.byType(TenturaAvatar)),
            findsOneWidget,
            reason: 'The first revealed item must already contain its avatar',
          );
          expect(
            setupAction,
            findsOneWidget,
            reason:
                'The first revealed item must already contain its setup link',
          );
          firstVisibleHeight = tester.getSize(item).height;
        }

        try {
          await _pumpInbox(
            tester,
            attentionRepo: repo,
            router: _HarnessRouter(),
            joinedProfile: profile,
          );
          await tester.pump(const Duration(milliseconds: 160));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          captureFrame();
          expect(
            firstVisibleHeight,
            isNull,
            reason: 'Mounted content behind the gate is not a reveal',
          );
          repo.offersResponse.complete(
            const ActivityOfferPage(),
          );
          repo.feedResponse.complete(
            AttentionFeed(
              summary: const AttentionSummary(),
              page: AttentionFeedPage(items: [receipt]),
            ),
          );
          // Observe individual frames, including the very first reveal. A fix
          // may either keep the gate closed or reserve the final card layout.
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 10));
            captureFrame();
          }
          expect(profile.requestedIds, contains('joined-person'));
          expect(profile.response.isCompleted, isFalse);
          profile.response.complete(_DelayedJoinedProfile.person);
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 10));
            captureFrame();
          }
          expect(card, findsOneWidget);
          expect(find.text('QA Bob'), findsOneWidget);
          expect(find.text('Add what QA Bob can help with'), findsOneWidget);
          expect(setupAction, findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(firstVisibleHeight, isNotNull);
          expect(
            firstVisibleHeight,
            tester.getSize(item).height,
            reason:
                'The first revealed item must have the same height '
                'as the card after the joined person resolves',
          );
        } finally {
          if (!profile.response.isCompleted) {
            profile.response.complete(_DelayedJoinedProfile.person);
          }
          if (!repo.offersResponse.isCompleted) _finishOffers(repo);
          if (!repo.feedResponse.isCompleted) _finishFeed(repo);
          await _frames(tester);
        }
      },
    );

    testWidgets(
      'reveals available offers after 2.5 seconds when updates stall',
      (tester) async {
        final repo = _ControlledAttentionRepo();
        try {
          // The harness only flushes microtasks: elapsed gate time is zero.
          await _pumpInbox(
            tester,
            attentionRepo: repo,
            router: _HarnessRouter(),
          );
          expect(repo.offerCalls, greaterThan(0));
          expect(repo.feedCalls, greaterThan(0));
          _finishOffers(repo);
          await tester.pump();
          await tester.pump();

          await tester.pump(const Duration(milliseconds: 2499));
          final beforeTimeout = _visibleFrame();
          expect(repo.feedResponse.isCompleted, isFalse);

          await tester.pump(const Duration(milliseconds: 2)); // 2501 ms
          expect(repo.feedResponse.isCompleted, isFalse);
          expect(find.text('Repair the garden gate'), findsOneWidget);
          expect(find.text('Delivery arranged for Friday'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // Revealing available data must not depend on the stalled source
          // finishing, nor re-arm the spinner on the next frame.
          await tester.pump(const Duration(seconds: 1));
          expect(repo.feedResponse.isCompleted, isFalse);
          expect(find.text('Repair the garden gate'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // A late response still fills the revealed list in place.
          _finishFeed(repo);
          await _frames(tester);
          expect(find.text('Repair the garden gate'), findsOneWidget);
          expect(find.text('Delivery arranged for Friday'), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // Assert last so the escape and late-response phases also execute
          // against today's screen, which reveals available offers too early.
          expect(
            beforeTimeout,
            (gateSpinners: 1, allSpinners: 1, offers: 0, updates: 0),
            reason:
                'At 2499 ms the gate must still withhold the partial list; '
                'at 2501 ms it must reveal available offers without waiting '
                'for the stalled updates source',
          );
        } finally {
          if (!repo.offersResponse.isCompleted) _finishOffers(repo);
          if (!repo.feedResponse.isCompleted) _finishFeed(repo);
          await _frames(tester);
        }
      },
    );

    for (final offersFirst in [true, false]) {
      testWidgets(
        offersFirst
            ? 'withholds loaded offers until updates arrive and keeps the list during refresh'
            : 'withholds loaded updates until offers arrive and keeps the list during refresh',
        (tester) async {
          final repo = _ControlledAttentionRepo();
          try {
            await _pumpInbox(
              tester,
              attentionRepo: repo,
              router: _HarnessRouter(),
            );
            expect(repo.offerCalls, greaterThan(0));
            expect(repo.feedCalls, greaterThan(0));
            final mounted = _visibleFrame();
            await tester.pump(const Duration(milliseconds: 149));
            final beforeDelay = _visibleFrame();
            await tester.pump(const Duration(milliseconds: 2));
            final pending = _visibleFrame();

            if (offersFirst) {
              _finishOffers(repo);
            } else {
              _finishFeed(repo);
            }
            await _frames(tester);
            final partial = _visibleFrame();

            if (offersFirst) {
              _finishFeed(repo);
            } else {
              _finishOffers(repo);
            }
            await _frames(tester);
            expect(find.text('Repair the garden gate'), findsOneWidget);
            expect(find.text('Delivery arranged for Friday'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              find.descendant(
                of: find.byType(TenturaFirstLoadGate),
                matching: find.byType(CircularProgressIndicator),
              ),
              findsNothing,
              reason:
                  'Completing both initial sources removes the gate spinner',
            );

            final context = tester.element(find.byType(ActivityStreamView));
            repo.offersResponse = Completer<ActivityOfferPage>();
            repo.feedResponse = Completer<AttentionFeed>();
            final offerCalls = repo.offerCalls;
            final feedCalls = repo.feedCalls;
            final refresh = Future.wait([
              context.read<ActivityOffersCubit>().loadFirst(),
              context.read<UpdatesFeedCubit>().refresh(),
            ]);
            await _frames(tester);
            expect(repo.offerCalls, greaterThan(offerCalls));
            expect(repo.feedCalls, greaterThan(feedCalls));
            expect(find.text('Repair the garden gate'), findsOneWidget);
            expect(find.text('Delivery arranged for Friday'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            _finishOffers(repo);
            _finishFeed(repo);
            await refresh;
            await _frames(tester);
            expect(find.text('Repair the garden gate'), findsOneWidget);
            expect(find.text('Delivery arranged for Friday'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);

            // Exercise the screen's actual refresh callback through a gesture,
            // in addition to the background source refresh above. The pull
            // indicator is expected; a first-load spinner must not return.
            repo.offersResponse = Completer<ActivityOfferPage>();
            repo.feedResponse = Completer<AttentionFeed>();
            final pullOfferCalls = repo.offerCalls;
            final pullFeedCalls = repo.feedCalls;
            await tester.drag(
              find.byType(CustomScrollView),
              const Offset(0, 400),
            );
            await tester.pump(const Duration(milliseconds: 300));
            await _frames(tester);
            expect(repo.offerCalls, greaterThan(pullOfferCalls));
            expect(repo.feedCalls, greaterThan(pullFeedCalls));
            expect(find.byType(RefreshProgressIndicator), findsOneWidget);
            expect(find.text('Repair the garden gate'), findsOneWidget);
            expect(find.text('Delivery arranged for Friday'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            _finishOffers(repo);
            _finishFeed(repo);
            await tester.pumpAndSettle();
            expect(find.byType(RefreshProgressIndicator), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.text('Repair the garden gate'), findsOneWidget);
            expect(find.text('Delivery arranged for Friday'), findsOneWidget);

            // Assert captured frames last so release and refresh are exercised
            // even while the screen still exposes its independent sources.
            expect(
              (
                mounted: mounted,
                beforeDelay: beforeDelay,
                pending: pending,
                partial: partial,
              ),
              (
                mounted: (
                  gateSpinners: 0,
                  allSpinners: 0,
                  offers: 0,
                  updates: 0,
                ),
                beforeDelay: (
                  gateSpinners: 0,
                  allSpinners: 0,
                  offers: 0,
                  updates: 0,
                ),
                pending: (
                  gateSpinners: 1,
                  allSpinners: 1,
                  offers: 0,
                  updates: 0,
                ),
                partial: (
                  gateSpinners: 1,
                  allSpinners: 1,
                  offers: 0,
                  updates: 0,
                ),
              ),
              reason:
                  'Until both primary sources finish, Activity must show '
                  'no partial list, no spinner before 150 ms, and only the '
                  'shared gate spinner after 150 ms',
            );
          } finally {
            if (!repo.offersResponse.isCompleted) _finishOffers(repo);
            if (!repo.feedResponse.isCompleted) _finishFeed(repo);
            await _frames(tester);
          }
        },
      );
    }
  });
}
