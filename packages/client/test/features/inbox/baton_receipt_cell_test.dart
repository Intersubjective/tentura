import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/attention_case_factory.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

class _HarnessRouter extends Mock implements StackRouter {}

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
  AttentionActorProfilesCase? actorProfiles,
}) async {
  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = buildAttentionCase(
    repository: attentionRepo,
    accounts: accounts,
    realtimeSyncCase: sync.case_,
    blockCase: noopBlockCase(),
    feedSessions: FeedSessionRegistry(),
    logger: Logger('activity-stream-test'),
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
    actorProfiles: actorProfiles ?? buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('activity-stream-test'),
    actorProfiles: actorProfiles ?? buildNoopAttentionActorProfiles(),
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
  if (!GetIt.I.isRegistered<AppNavigator>()) registerFakeAppNavigator();
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
    // As the server writes it: a baton ask reaches its candidate personally
    // (#189 — `batonCandidate`), the other two do not.
    'personal': type == 'batonAsked',
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
  late FakeAppNavigator navigator;
  setUp(() {
    navigator = registerFakeAppNavigator();
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
                (_, 'batonAsked') => 'Anna asks if you can help',
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
              expect(navigator.named('openFromUpdate'), hasLength(1));
              final destination = attentionDestination(
                navigator.openedReceipts.single,
              );
              expect(
                destination.path,
                beaconKind == 1 ? '$kPathPostView/B1' : '$kPathBeaconView/B1',
              );
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

  group('pair baton receipts', () {
    const anna = Profile(id: 'u-anna', displayName: 'Anna');
    const xenia = Profile(id: 'u-xenia', displayName: 'Xenia');

    AttentionReceipt receiptOf(
      String type,
      int beaconKind, {
      String actorId = 'u-anna',
      Map<String, Object?> payload = const {},
    }) => AttentionReceipt(
      id: 'receipt-$type',
      category: 'coordination',
      kind: type,
      priority: 'normal',
      title: 'Server English title',
      body: 'Carry the boxes',
      actionUrl: '/beacon/view/B1?tab=threads&messageId=M1',
      createdAt: DateTime.utc(2026, 10, 5, 12),
      collapsedCount: 1,
      presentationPayloadJson: jsonEncode({
        'eventType': type,
        // Partner invitations and answers reach one person directly.
        'personal': type != 'batonTaken',
        'excerpt': 'Carry the boxes',
        // Extra payload fields must never become rendered names.
        'candidates': [
          {'userId': 'other-candidate', 'title': 'Private candidate'},
        ],
        ...payload,
      }),
      presentationKey: switch (type) {
        'batonPartnerAsked' => 'baton_partner_asked',
        'batonPartnerAnswered' => 'baton_partner_answered',
        _ => 'baton_taken',
      },
      actorUserId: actorId,
      beaconId: 'B1',
      beaconKind: beaconKind,
      destinationKind: 'beacon_room_message',
      targetEntityId: 'M1',
      surface: AttentionSurface.activity,
    );

    AttentionReceipt groupedOf(AttentionReceipt event) => event.copyWith(
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
    );

    // (name, receipt builder, EN headline, RU headline)
    final cases = <(String, AttentionReceipt Function(int), String, String)>[
      (
        'partner asked',
        (k) => receiptOf('batonPartnerAsked', k),
        'Anna wants to take it on together with you',
        'Anna предлагает взяться вместе',
      ),
      (
        'partner answered accepted',
        (k) => receiptOf(
          'batonPartnerAnswered',
          k,
          actorId: 'u-xenia',
          payload: {'accepted': true},
        ),
        'Xenia will take it on with you',
        'Xenia возьмётся вместе с вами',
      ),
      (
        'partner answered declined',
        (k) => receiptOf(
          'batonPartnerAnswered',
          k,
          actorId: 'u-xenia',
          payload: {'accepted': false},
        ),
        "Xenia can't join you. Answer again",
        'Xenia не сможет присоединиться. Ответьте ещё раз',
      ),
      (
        'pair taken',
        (k) => receiptOf(
          'batonTaken',
          k,
          actorId: 'author',
          payload: {'withUserId': 'u-xenia'},
        ),
        'You and Xenia took it: Carry the boxes',
        'Вы и Xenia взялись: Carry the boxes',
      ),
    ];

    Future<void> openFeed(
      WidgetTester tester,
      AttentionReceipt receipt,
      String locale, {
      List<Profile> known = const [anna, xenia],
    }) async {
      final profiles = AttentionActorProfilesCase(
        _KnownProfiles(known),
        _Accounts(),
      );
      addTearDown(profiles.dispose);
      GetIt.I.registerSingleton<AttentionActorProfilesCase>(profiles);
      final boot = await _boot(
        inboxRepo: FakeInboxRepository(),
        attentionRepo: _FeedAttentionRepo(firstPage: [receipt]),
        actorProfiles: profiles,
      );
      addTearDown(boot.dispose);
      await _pumpStreamView(
        tester,
        boot: boot,
        locale: Locale(locale),
        logicalSize: const Size(600, 1100),
      );
    }

    for (final locale in ['en', 'ru']) {
      for (final beaconKind in [0, 1]) {
        for (final grouped in [false, true]) {
          for (final (name, build, en, ru) in cases) {
            testWidgets(
              '$name $locale host=$beaconKind grouped=$grouped shows the '
              'named line and opens the room at the baton message',
              (tester) async {
                final event = build(beaconKind);
                await openFeed(
                  tester,
                  grouped ? groupedOf(event) : event,
                  locale,
                );
                final expected = locale == 'ru' ? ru : en;
                final copy = find.textContaining(expected, findRichText: true);
                expect(copy, findsOneWidget);
                // The «taken» line already quotes the ask in its headline, so
                // there is no separate body to find; the other kinds show it
                // as the body under the headline.
                if (name != 'pair taken') {
                  expect(
                    find.textContaining('Carry the boxes'),
                    findsOneWidget,
                  );
                }
                expect(find.textContaining('Private candidate'), findsNothing);
                expect(find.textContaining('other-candidate'), findsNothing);
                expect(
                  find.textContaining('Server English title'),
                  findsNothing,
                );
                expect(tester.takeException(), isNull);

                await tester.tap(copy);
                await _pumpFrames(tester);
                expect(navigator.named('openFromUpdate'), hasLength(1));
                final destination = attentionDestination(
                  navigator.openedReceipts.single,
                );
                expect(
                  destination.path,
                  beaconKind == 1 ? '$kPathPostView/B1' : '$kPathBeaconView/B1',
                );
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

    for (final locale in ['en', 'ru']) {
      for (final grouped in [false, true]) {
        testWidgets(
          'taken without a partner id reads the solo line $locale '
          'grouped=$grouped',
          (tester) async {
            final event = receiptOf('batonTaken', 0, actorId: 'author');
            await openFeed(tester, grouped ? groupedOf(event) : event, locale);
            expect(
              find.textContaining(
                locale == 'ru'
                    ? 'Вы взялись: Carry the boxes'
                    : 'You took it: Carry the boxes',
                findRichText: true,
              ),
              findsOneWidget,
            );
            expect(find.textContaining('Xenia'), findsNothing);
          },
        );

        testWidgets(
          'taken with a partner the client cannot name reads the solo line '
          '$locale grouped=$grouped',
          (tester) async {
            final event = receiptOf(
              'batonTaken',
              0,
              actorId: 'author',
              payload: {'withUserId': 'u-unknown'},
            );
            await openFeed(
              tester,
              grouped ? groupedOf(event) : event,
              locale,
              known: const [anna],
            );
            expect(
              find.textContaining(
                locale == 'ru'
                    ? 'Вы взялись: Carry the boxes'
                    : 'You took it: Carry the boxes',
                findRichText: true,
              ),
              findsOneWidget,
            );
            expect(find.textContaining('u-unknown'), findsNothing);
            expect(find.textContaining(' and '), findsNothing);
            expect(find.textContaining(' и '), findsNothing);
          },
        );
      }
    }
  });
}

/// Profiles the client already knows by id.
final class _KnownProfiles extends Fake implements ProfileRepositoryPort {
  _KnownProfiles(this._known);

  final List<Profile> _known;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final p in _known)
      if (ids.contains(p.id)) p,
  ];
}

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}
