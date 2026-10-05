import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

class _HarnessRouter extends Mock implements StackRouter {}

class _MockRootRouter extends Mock implements RootRouter {
  final opened = <AttentionReceipt>[];
  @override
  Future<void> openFromUpdate(AttentionReceipt receipt) async {
    opened.add(receipt);
  }
}

class _TestInboxCubit extends Cubit<InboxState> implements InboxCubit {
  _TestInboxCubit(super.initialState);

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

  final dismissedTombstones = <String>[];

  @override
  Future<void> dismissTombstone(String beaconId) async =>
      dismissedTombstones.add(beaconId);
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

class _FeedAttentionRepo extends ConfigurableActivityOffersAttentionRepo {
  _FeedAttentionRepo({
    required this.firstPage,
  });

  final List<AttentionReceipt> firstPage;
  final List<AttentionReceipt> secondPage = const [];
  int fetchCalls = 0;
  final List<String> historyCalls = [];

  @override
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) async {
    historyCalls.add(beaconId);
    return const AttentionFeedPage();
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    fetchCalls++;
    if (cursor == null || cursor.isEmpty) {
      return AttentionFeed(
        summary: const AttentionSummary(),
        page: AttentionFeedPage(items: firstPage),
      );
    }
    return AttentionFeed(
      summary: const AttentionSummary(),
      page: AttentionFeedPage(items: secondPage),
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

Future<void> _pumpFrames(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Boot {
  _Boot({
    required this.offers,
    required this.stream,
    required this.inboxRepo,
    required this.attentionRepo,
    required this.attention,
    required this.accounts,
  });

  final ActivityOffersCubit offers;
  final UpdatesFeedCubit stream;
  final FakeInboxRepository inboxRepo;
  final _FeedAttentionRepo attentionRepo;
  final AttentionCase attention;
  final _Accounts accounts;

  Future<void> dispose() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await accounts.close();
  }
}

Future<_Boot> _boot({
  required FakeInboxRepository inboxRepo,
  required _FeedAttentionRepo attentionRepo,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('activity-stream-test'),
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
    logger: Logger('activity-stream-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await attention.refresh();
  return _Boot(
    offers: offers,
    stream: stream,
    inboxRepo: inboxRepo,
    attentionRepo: attentionRepo,
    attention: attention,
    accounts: accounts,
  );
}

Future<void> _pumpStreamView(
  WidgetTester tester, {
  required _Boot boot,
  _TestInboxCubit? inbox,
  Size logicalSize = const Size(360, 640),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final inboxCubit =
      inbox ??
      _TestInboxCubit(
        const InboxState(projectionLoaded: true),
      );

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(boot.attention);
  ensureNoopAttentionActorProfilesRegistered();
  if (!GetIt.I.isRegistered<RootRouter>()) {
    GetIt.I.registerSingleton<RootRouter>(_MockRootRouter());
  }
  addTearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      await GetIt.I.unregister<AttentionCase>();
    }
  });

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: boot.offers),
          BlocProvider<UpdatesFeedCubit>.value(value: boot.stream),
          BlocProvider<InboxCubit>.value(value: inboxCubit),
        ],
        child: MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              textScaler: TextScaler.noScaling,
            ),
            child: const TenturaResponsiveScope(
              child: Scaffold(body: ActivityStreamView()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await _pumpFrames(tester, frames: 8);
}

AttentionReceipt _batonReceipt(String type, int beaconKind) => AttentionReceipt(
  id: 'receipt-$type',
  category: 'coordination',
  kind: type,
  priority: 'normal',
  title: type == 'batonAsked' ? 'Anna' : 'Server English title',
  body: 'Carry the boxes',
  actionUrl: '/beacon/view/B1?tab=threads&messageId=M1',
  createdAt: DateTime.utc(2026, 10, 5, 12),
  collapsedCount: 1,
  presentationPayloadJson: jsonEncode({
    'eventType': type,
    'excerpt': 'Carry the boxes',
    // Extra payload fields must never become rendered candidate names.
    'candidates': [
      {'userId': 'other-candidate', 'title': 'Private candidate'},
    ],
  }),
  presentationKey: switch (type) {
    'batonAsked' => 'baton_asked',
    'batonTaken' => 'baton_taken',
    _ => 'baton_all_answered',
  },
  actorUserId: 'author',
  beaconId: 'B1',
  beaconKind: beaconKind,
  destinationKind: 'beacon_room_message',
  targetEntityId: 'M1',
  surface: AttentionSurface.activity,
);

void main() {
  setUp(() {
    GetIt.I.registerSingleton<RootRouter>(_MockRootRouter());
  });
  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final locale in ['en', 'ru']) {
    for (final beaconKind in [0, 1]) {
      for (final grouped in [false, true]) {
        for (final type in ['batonAsked', 'batonTaken', 'batonAllAnswered']) {
          testWidgets(
            '$type $locale host=$beaconKind grouped=$grouped copy and message navigation',
            (tester) async {
              final event = _batonReceipt(type, beaconKind);
              final receipt = grouped
                  ? event.copyWith(
                      id: 'group-B1',
                      itemKind: AttentionItemKind.requestActivity,
                      title: 'Request or Post title',
                      kind: 'roomActivityLowPriority',
                      presentationKey: null,
                      presentationPayloadJson: '{}',
                      destinationKind: 'beacon',
                      targetEntityId: 'B1',
                      eventsPreview: [event],
                      eventTotal: 1,
                      eventUnseenCount: 1,
                    )
                  : event;
              final boot = await _boot(
                inboxRepo: FakeInboxRepository(),
                attentionRepo: _FeedAttentionRepo(firstPage: [receipt]),
              );
              addTearDown(boot.dispose);
              await _pumpStreamView(
                tester,
                boot: boot,
                locale: Locale(locale),
                logicalSize: const Size(600, 1100),
              );
              final expected = switch ((locale, type)) {
                ('ru', 'batonAsked') => 'Anna спрашивает, сможете ли вы помочь',
                ('ru', 'batonTaken') => 'Вы взялись: Carry the boxes',
                ('ru', _) => 'Все ответили на ваше «Кто возьмётся?»',
                (_, 'batonAsked') => 'Anna asks you can help',
                (_, 'batonTaken') => 'You took it: Carry the boxes',
                _ => "Everyone answered your «Who'll take it?»",
              };
              final copy = find.textContaining(expected, findRichText: true);
              expect(copy, findsOneWidget);
              if (type == 'batonAsked') {
                expect(find.textContaining('Carry the boxes'), findsOneWidget);
              }
              expect(find.textContaining('Private candidate'), findsNothing);
              expect(find.textContaining('other-candidate'), findsNothing);
              expect(find.textContaining('Server English title'), findsNothing);
              expect(tester.takeException(), isNull);

              await tester.tap(copy);
              await _pumpFrames(tester);
              final router = GetIt.I<RootRouter>() as _MockRootRouter;
              expect(router.opened, hasLength(1));
              final destination = attentionDestination(router.opened.single);
              expect(destination.path, '$kPathBeaconView/B1');
              expect(
                destination.queryParameters[kQueryBeaconViewTab],
                kBeaconViewTabThreads,
              );
              expect(destination.queryParameters[kQueryMessageId], 'M1');
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}
