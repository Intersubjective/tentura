// Activity's forward outcome row (a tombstone) carries ONE unread tick when
// somebody else relabelled the forward and the viewer has not seen it; the
// viewer's own relabel, and a row whose outcome never changed, carry none.
// Opening the row, or marking it seen, clears the tick.
//
// Real path: the server's stream rows as `attentionFeed` JSON → the
// production `AttentionRepository` mapper → `AttentionCase` →
// `UpdatesFeedCubit` → `ActivityStreamView`. The server encodes the tick as
// `seenAt == null` on the `inbox:<beaconId>` forward row
// (docs/contracts/attention-active-attention-axis.json § forwardOutcomeTick).

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/widget/activity_stream_view.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_indicators.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/forward_outcome_wire.dart';
import '../../support/noop_attention_actor_profiles.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'activity_offers_test_support.dart';
import 'author_invite_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

/// The Request whose forward somebody relabelled.
const _ticked = 'Bticked000001';

/// A Request with a live grouped card on the same page.
const _carded = 'Bcarded000001';

/// When the viewer was forwarded the Request: `entry_at`, which is also the
/// forward row's `latest_forward_at`.
const _entryAt = '2026-11-01T09:00:00.000Z';

/// When the forward's status changed (`outcome_changed_at`).
const _outcomeChangedAt = '2026-11-03T15:30:00.000Z';

const _cardAt = '2026-11-02T12:00:00.000Z';

/// The stream server: holds the rows as the server would send them, serves
/// every fetch through the real client mapper, and moves `seen_at` the way
/// the server's `markSeen` with an `inbox:` id does.
final class _StreamServer extends ConfigurableActivityOffersAttentionRepo {
  _StreamServer(this.rows);

  /// The server's current stream rows (wire JSON).
  List<Map<String, dynamic>> rows;

  /// Every `markSeen` call, in order.
  final markSeenCalls = <List<String>>[];

  /// When set, `markSeen` waits for it, then fails.
  Completer<void>? failMarkSeenAfter;

  /// First-page `attentionFeed` fetches the client made, in order.
  int firstPageFetches = 0;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async {
    if (cursor == null || cursor.isEmpty) firstPageFetches++;
    return _page(view: view, cursor: cursor);
  }

  Future<AttentionFeed> _page({
    required AttentionView view,
    String? cursor,
  }) async => AttentionFeed(
    summary: const AttentionSummary(),
    page: AttentionFeedPage(
      items: cursor == null || cursor.isEmpty
          ? await mapStreamRowsThroughRepository(rows, view: view)
          : const [],
    ),
  );

  @override
  Future<int> markSeen(List<String> ids) async {
    markSeenCalls.add(List.of(ids));
    final gate = failMarkSeenAfter;
    if (gate != null) {
      await gate.future;
      throw StateError('markSeen offline');
    }
    // The server: an inbox:<beaconId> markSeen sets outcome_seen_at, so the
    // row comes back with seen_at = latest_forward_at at the same created_at.
    rows = [
      for (final row in rows)
        if (ids.contains(row['id']) && row['itemKind'] == 'forward')
          {...row, 'seenAt': _entryAt}
        else
          row,
    ];
    return ids.length;
  }

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  /// «Read all» sweeps after marking seen; nothing is dismissible here.
  @override
  Future<AttentionDismissAllResult> dismissAll({
    required String operationId,
    int? maxBatches,
  }) async => AttentionDismissAllResult(
    operationId: operationId,
    status: AttentionOperationStatus.complete,
  );

  /// Every `markAllSeen` call, in order (the surface it named).
  final markAllSeenCalls = <AttentionSurface?>[];

  /// The server after «Read all» (#601-a follow-up): `markAllSeen` also sets
  /// the viewer's `outcome_seen_at` on forward rows, so a forward row comes
  /// back with `seen_at = latest_forward_at` at the same `created_at`.
  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async {
    markAllSeenCalls.add(surface);
    rows = [
      for (final row in rows)
        if (row['itemKind'] == 'forward') {...row, 'seenAt': _entryAt} else row,
    ];
    return 0;
  }

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;

  @override
  Future<AttentionClearSnapshot> clearSnapshot({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async => AttentionClearSnapshot(snapshotToken: 'snap-$receiptId');

  @override
  Future<AttentionClearResult> clear({
    required String snapshotToken,
    required String operationId,
  }) async => AttentionClearResult(
    operationId: operationId,
    status: AttentionOperationStatus.complete,
  );
}

class _HarnessRouter extends Mock implements StackRouter {}

class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);
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
  Future<void> dismissTombstone(String beaconId) async {}

  @override
  Future<void> unreject(String beaconId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness({
    required this.server,
    required this.stream,
    required this.navigator,
  });

  final _StreamServer server;
  final UpdatesFeedCubit stream;
  final FakeAppNavigator navigator;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The first frame drawn after a state change. The cubit hears the ack
/// through async streams, so the change lands during the microtask flush
/// that ends one `pump()`; that pump had no frame scheduled, and the rebuild
/// is drawn by the next one.
Future<void> _nextFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<_Harness> _pumpActivity(
  WidgetTester tester,
  List<Map<String, dynamic>> rows, {
  Locale locale = const Locale('en'),
}) async {
  await usePhoneSurface(tester);
  // The view itself is the phone, so MediaQuery reads 375×667 as well.
  tester.view.physicalSize = kPhoneSurface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final server = _StreamServer(rows);
  final inboxRepo = FakeInboxRepository();
  wireActivityOffersV2(inbox: inboxRepo, attention: server, items: const []);

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attention = AttentionCase(
    server,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('forward-outcome-tick-test'),
  );
  final inboxCase = buildTestInboxCase(
    inboxRepo,
    buildTestBeaconThreadsCase(),
    forwardRepository: _ForwardRepo(),
    realtimeSyncCase: sync.case_,
  );
  accounts.emit('viewer');
  final offers = ActivityOffersCubit(
    userId: 'viewer',
    inboxCase: inboxCase,
    attentionCase: attention,
    authorInviteCase: buildAuthorInviteCase(FakeAuthorInvitePort()),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await offers.loadFirst();
  final stream = UpdatesFeedCubit(
    destinationId: AttentionFeedDestinationId.activityStream,
    attention: attention,
    setup: NoopInviteAcceptedSetupPort(),
    realtime: sync.case_,
    logger: Logger('forward-outcome-tick-test'),
    actorProfiles: buildNoopAttentionActorProfiles(),
  );
  await stream.stream.firstWhere((state) => state.firstLoadDone);

  if (GetIt.I.isRegistered<AttentionCase>()) {
    GetIt.I.unregister<AttentionCase>();
  }
  GetIt.I.registerSingleton<AttentionCase>(attention);
  ensureNoopAttentionActorProfilesRegistered();
  // A second harness in one test keeps the navigator the first registered.
  final registered = GetIt.I.isRegistered<AppNavigator>()
      ? GetIt.I<AppNavigator>()
      : null;
  final navigator = registered is FakeAppNavigator
      ? registered
      : registerFakeAppNavigator();

  await tester.pumpWidget(
    StackRouterScope(
      controller: _HarnessRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ActivityOffersCubit>.value(value: offers),
          BlocProvider<UpdatesFeedCubit>.value(value: stream),
          BlocProvider<InboxCubit>.value(
            value: _TestInboxCubit(const InboxState(projectionLoaded: true)),
          ),
        ],
        child: MaterialApp(
          locale: locale,
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
  await _settle(tester);

  addTearDown(() async {
    await offers.close();
    await stream.close();
    await attention.dispose();
    await sync.port.dispose();
  });
  return _Harness(server: server, stream: stream, navigator: navigator);
}

/// The Activity row drawn for the forward of [beaconId].
Finder _forwardRow(String beaconId) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.identifier == TestIds.activityForwardRow(beaconId),
  description: 'Activity forward row for $beaconId',
);

/// The tombstone row's unread tick: the design-system unread dot drawn on
/// [TombstoneRow], keyed like the row's other controls
/// (`tombstone-row-dismiss`, `tombstone-row-restore`).
const _tombstoneUnreadDotKey = Key('tombstone-row-unread-dot');

/// Unread ticks on the forward row of [beaconId].
int _rowDots(String beaconId) => find
    .descendant(
      of: _forwardRow(beaconId),
      matching: find.byKey(_tombstoneUnreadDotKey),
    )
    .evaluate()
    .length;

/// Every unread dot drawn inside the grouped card: its own indicator, the
/// mini-cards' dots, and (never) a tombstone tick.
int _cardDots() {
  final card = find.byType(RequestAttentionCard);
  expect(card, findsOneWidget);
  var dots = 0;
  for (final key in const [
    RequestAttentionIndicators.dotKey,
    UpdatesFeedTile.unreadDotKey,
    _tombstoneUnreadDotKey,
  ]) {
    dots += find
        .descendant(of: card, matching: find.byKey(key))
        .evaluate()
        .length;
  }
  return dots;
}

/// Whether opening led to Request [beaconId], whichever navigator entry
/// point the row uses.
bool _navigatedToRequest(FakeAppNavigator navigator, String beaconId) =>
    navigator.openedReceipts.any((r) => r.beaconId == beaconId) ||
    navigator.intents.any(
      (intent) => intent.args.values.any((value) => value == beaconId),
    );

Map<String, dynamic> _tickedRow({String? seenAt}) => forwardOutcomeRowWire(
  beaconId: _ticked,
  createdAt: _outcomeChangedAt,
  seenAt: seenAt,
);

Map<String, dynamic> _groupedCardRow() => attentionStreamRowWire(
  id: 'group-$_carded',
  itemKind: 'requestActivity',
  beaconId: _carded,
  createdAt: _cardAt,
  title: 'Garden cleanup',
  eventTotal: 1,
  eventUnseenCount: 1,
  eventsPreview: [
    attentionStreamRowWire(
      id: 'Ecarded000001',
      itemKind: 'receipt',
      kind: 'newRelay',
      beaconId: _carded,
      createdAt: _cardAt,
      title: 'Garden cleanup',
      actorUserId: 'Umaria0000001',
    ),
  ],
);

void main() {
  tearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<AppNavigator>()) {
      await GetIt.I.unregister<AppNavigator>();
    }
  });

  group('forward outcome row unread tick on Activity', () {
    testWidgets('a relabel by somebody else shows one unread dot on the row', (
      tester,
    ) async {
      await _pumpActivity(tester, [_tickedRow()]);

      expect(_forwardRow(_ticked), findsOneWidget);
      expect(
        find.descendant(
          of: _forwardRow(_ticked),
          matching: find.byType(TombstoneRow),
        ),
        findsOneWidget,
      );
      expect(_rowDots(_ticked), 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the viewer's own relabel shows no unread dot", (
      tester,
    ) async {
      // The server answers the viewer's own relabel with
      // seen_at = latest_forward_at.
      await _pumpActivity(tester, [_tickedRow(seenAt: _entryAt)]);

      expect(_forwardRow(_ticked), findsOneWidget);
      expect(_rowDots(_ticked), 0);
    });

    testWidgets(
      'a row whose outcome never changed shows no dot, and a card keeps its own',
      (tester) async {
        await _pumpActivity(tester, [
          _groupedCardRow(),
          forwardOutcomeRowWire(
            beaconId: _ticked,
            createdAt: _entryAt,
            seenAt: _entryAt,
          ),
        ]);

        expect(_forwardRow(_ticked), findsOneWidget);
        expect(_rowDots(_ticked), 0);
        // The card's own unseen event keeps exactly its one indicator dot.
        expect(
          find.descendant(
            of: find.byType(RequestAttentionCard),
            matching: find.byKey(RequestAttentionIndicators.dotKey),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a ticked row next to a card: the tick neither adds to nor removes '
      "the card's dot",
      (tester) async {
        // The same card on a page without the forward row.
        await _pumpActivity(tester, [_groupedCardRow()]);
        final cardDotsAlone = _cardDots();
        expect(cardDotsAlone, greaterThan(0));

        await _pumpActivity(tester, [_tickedRow(), _groupedCardRow()]);

        expect(_cardDots(), cardDotsAlone);
        expect(_rowDots(_ticked), 1);
      },
    );

    testWidgets(
      'opening the ticked row marks inbox:<beaconId> seen and clears the dot',
      (tester) async {
        final harness = await _pumpActivity(tester, [_tickedRow()]);
        expect(_rowDots(_ticked), 1);

        await tester.tap(
          find.descendant(
            of: _forwardRow(_ticked),
            matching: find.text('Book swap Sunday'),
          ),
        );
        await _settle(tester);

        expect(harness.server.markSeenCalls, [
          ['inbox:$_ticked'],
        ]);
        expect(_rowDots(_ticked), 0);
        // Opening still opens the Request.
        expect(_navigatedToRequest(harness.navigator, _ticked), isTrue);
      },
    );

    testWidgets(
      'marking the row seen clears the dot at once and after the refresh, '
      'and the row keeps its place',
      (tester) async {
        final harness = await _pumpActivity(tester, [
          _tickedRow(),
          _groupedCardRow(),
        ]);
        expect(_rowDots(_ticked), 1);
        final orderBefore = [
          for (final r in harness.stream.state.items) r.id,
        ];
        expect(orderBefore.first, 'inbox:$_ticked');

        unawaited(harness.stream.markSeen('inbox:$_ticked'));
        await _nextFrame(tester);
        expect(
          _rowDots(_ticked),
          0,
          reason: 'the optimistic ack clears the tick at once',
        );
        await _settle(tester);

        expect(harness.server.markSeenCalls, [
          ['inbox:$_ticked'],
        ]);
        expect(_rowDots(_ticked), 0);
        final ticked = harness.stream.state.items.firstWhere(
          (r) => r.id == 'inbox:$_ticked',
        );
        expect(ticked.seenAt, DateTime.parse(_entryAt));
        expect(ticked.createdAt, DateTime.parse(_outcomeChangedAt));
        expect([for (final r in harness.stream.state.items) r.id], orderBefore);
        expect(
          tester.getTopLeft(_forwardRow(_ticked)).dy,
          lessThan(tester.getTopLeft(find.byType(RequestAttentionCard)).dy),
        );
      },
    );

    testWidgets(
      'Read all never brings the forward tick back: the refetch the server '
      'answers keeps the row seen, in place',
      (tester) async {
        final harness = await _pumpActivity(tester, [
          _tickedRow(),
          _groupedCardRow(),
        ]);
        expect(_rowDots(_ticked), 1);
        final orderBefore = [
          for (final r in harness.stream.state.items) r.id,
        ];
        final fetchesBefore = harness.server.firstPageFetches;

        // Whether the forward row carries the tick in every state the cubit
        // emits while Read all runs (an optimistic clear that the refetch
        // reverts would show as seen, then ticked again).
        final tickHistory = <bool>[];
        final sub = harness.stream.stream.listen((state) {
          for (final r in state.items) {
            if (r.id == 'inbox:$_ticked') tickHistory.add(r.seenAt == null);
          }
        });
        addTearDown(sub.cancel);

        final ok = await harness.stream.markAllSeen();
        await _settle(tester);

        expect(ok, isTrue);
        expect(harness.server.markAllSeenCalls, isNotEmpty);
        expect(
          harness.server.firstPageFetches,
          greaterThan(fetchesBefore),
          reason: 'Read all is followed by a refetch of the stream',
        );
        expect(tickHistory, isNotEmpty);
        final firstSeen = tickHistory.indexOf(false);
        expect(firstSeen, isNonNegative, reason: 'the tick was cleared');
        expect(
          tickHistory.skip(firstSeen).every((ticked) => !ticked),
          isTrue,
          reason: 'once cleared the tick never returns: $tickHistory',
        );
        expect(_rowDots(_ticked), 0);
        final ticked = harness.stream.state.items.firstWhere(
          (r) => r.id == 'inbox:$_ticked',
        );
        expect(ticked.seenAt, DateTime.parse(_entryAt));
        expect(ticked.createdAt, DateTime.parse(_outcomeChangedAt));
        expect([for (final r in harness.stream.state.items) r.id], orderBefore);
      },
    );

    testWidgets('a failed mark-seen rolls back and the dot comes back', (
      tester,
    ) async {
      final harness = await _pumpActivity(tester, [_tickedRow()]);
      expect(_rowDots(_ticked), 1);

      final gate = Completer<void>();
      harness.server.failMarkSeenAfter = gate;
      // Only the rollback is asserted; how the failure is reported is not.
      unawaited(
        harness.stream
            .markSeen('inbox:$_ticked')
            .then<void>((_) {}, onError: (Object _) {}),
      );
      await _nextFrame(tester);
      expect(_rowDots(_ticked), 0);

      gate.complete();
      await _settle(tester);

      expect(harness.server.markSeenCalls, [
        ['inbox:$_ticked'],
      ]);
      expect(_rowDots(_ticked), 1);
    });
  });

  testWidgets(
    'RU 375×667: a ticked outcome row reads its sentence with one dot and '
    'no overflow',
    (tester) async {
      await _pumpActivity(tester, [
        _tickedRow(),
        _groupedCardRow(),
      ], locale: const Locale('ru'));

      expect(
        MediaQuery.sizeOf(tester.element(find.byType(ActivityStreamView))),
        const Size(375, 667),
      );
      expect(
        tester.getSize(find.byType(ActivityStreamView)).width,
        375,
      );
      expect(
        find.descendant(
          of: _forwardRow(_ticked),
          matching: find.text(L10nRu().activityForwardOutcomeWatching),
        ),
        findsOneWidget,
      );
      expect(_rowDots(_ticked), 1);
      expect(tester.takeException(), isNull);
    },
  );
}
