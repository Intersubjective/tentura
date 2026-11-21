// Shared harness for the copied-fact tests: the origin line, «Use in another
// Request», arrival at the source, the history highlight and the «Earlier
// history» footer.
//
// Navigation runs on the real RootRouter (only page bodies are stubbed), so
// a test reads the real URL before and after a tap. Real-path tests answer
// BeaconFactCardOrigin through [OriginWire]: HTTP -> Ferry -> the real
// BeaconFactCardRepository mapping -> BeaconThreadsCase -> the widget.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';

const kCopyBeaconId = 'Bcopy00000001';
const kCopyFactId = 'Fcopy00000001';
const kSourceBeaconId = 'Bsource000001';
const kSourceFactId = 'Fsource000001';
const kSourceFactText = 'Key is under the mat, red door';
const kCopyFactText = 'Key is under the mat, blue door';

/// English wording fixed by the plan (D6/D7/D8, §6.1).
const kOriginFromRequest = 'Brought from another Request';
const kOriginFromPost = 'Brought from another Post';
const kOriginUnavailable = "The original isn't available to you";
const kChangedSinceCopied = 'Changed since it was copied';
const kSeeCopiedVersion = 'See the copied version';
const kUseInAnotherRequest = 'Use in another Request or Post';
const kEarlierHistoryFooter = 'Earlier history lives where this fact came from';
const kOpen = 'Open';

BeaconFactCard copiedFact({
  int? originBeaconKind = 0,
  String id = kCopyFactId,
  String beaconId = kCopyBeaconId,
  String factText = kCopyFactText,
}) => BeaconFactCard(
  id: id,
  beaconId: beaconId,
  factText: factText,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'Ubob',
  pinnedByTitle: 'Bob',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  status: BeaconFactCardStatusBits.active,
  lastEditedBy: 'Ucarol',
  lastEditedByTitle: 'Carol',
  originBeaconKind: originBeaconKind,
);

/// The fact at the source; it is not itself a copy.
BeaconFactCard sourceFact() => copiedFact(
  id: kSourceFactId,
  beaconId: kSourceBeaconId,
  factText: kSourceFactText,
  originBeaconKind: null,
);

BeaconFactOrigin unavailableOrigin() => (
  available: false,
  beaconId: null,
  factCardId: null,
  beaconKind: null,
  changedSinceCopy: null,
  canSeeCopiedRevision: null,
  copiedRevisionSeq: null,
);

BeaconFactOrigin availableOrigin() => (
  available: true,
  beaconId: kSourceBeaconId,
  factCardId: kSourceFactId,
  beaconKind: 0,
  changedSinceCopy: false,
  canSeeCopiedRevision: false,
  copiedRevisionSeq: null,
);

/// Author shown in the header of history revision [seq]; unique per row.
String revisionActor(int seq) => 'Actor-$seq-';

BeaconFactHistoryEntry historyRevision(int seq, String factCardId) {
  final createdAt = DateTime.utc(2026).add(Duration(minutes: seq));
  final text = 'Revision text number $seq';
  return seq == 1
      ? BeaconFactHistoryCreated(
          id: 'rev-$seq',
          factCardId: factCardId,
          seq: seq,
          factText: text,
          actorId: 'U$seq',
          actorTitle: revisionActor(seq),
          createdAt: createdAt,
        )
      : BeaconFactHistoryEdited(
          id: 'rev-$seq',
          factCardId: factCardId,
          seq: seq,
          factText: text,
          actorId: 'U$seq',
          actorTitle: revisionActor(seq),
          createdAt: createdAt,
        );
}

/// Answers `origin` with [originAnswer] and serves [historyLength]
/// revisions, newest first, in pages of 50.
class FakeOriginFactCardRepository extends FakeBeaconFactCardRepository {
  FakeOriginFactCardRepository({
    BeaconFactOrigin? originAnswer,
    this.historyLength = 3,
    this.facts = const [],
  }) : originAnswer = originAnswer ?? unavailableOrigin();

  BeaconFactOrigin originAnswer;
  final int historyLength;
  final List<BeaconFactCard> facts;
  static const pageSize = 50;

  final List<({String beaconId, String factCardId})> originCalls = [];
  final List<String?> revisionCursors = [];

  int get pagesRequested => revisionCursors.length;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async =>
      facts.where((f) => f.beaconId == beaconId).toList();

  @override
  Future<BeaconFactOrigin> origin({
    required String beaconId,
    required String factCardId,
  }) async {
    originCalls.add((beaconId: beaconId, factCardId: factCardId));
    return originAnswer;
  }

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async {
    revisionCursors.add(before);
    final page = before == null
        ? 0
        : int.parse(before.substring('cursor-'.length));
    final newest = historyLength - page * pageSize;
    final entries = <BeaconFactTimelineEntry>[
      for (var seq = newest; seq > 0 && seq > newest - pageSize; seq--)
        historyRevision(seq, factCardId),
    ];
    final more = newest - pageSize > 0;
    return (entries: entries, nextCursor: more ? 'cursor-${page + 1}' : null);
  }
}

void _unregister<T extends Object>() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<T>()) {
    // ignore: discarded_futures -- GetIt.unregister returns FutureOr; best-effort.
    getIt.unregister<T>();
  }
}

/// Registers [repository] as the app's fact card repository and a
/// BeaconThreadsCase over it, so the widget reaches it either way.
void registerFactRepository(BeaconFactCardRepository repository) {
  final getIt = GetIt.instance;
  _unregister<BeaconFactCardRepository>();
  _unregister<BeaconThreadsCase>();
  getIt
    ..registerSingleton<BeaconFactCardRepository>(repository)
    ..registerSingleton<BeaconThreadsCase>(
      BeaconThreadsCase(
        FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId),
        repository,
        FakePollingRepository(),
        FakeBeaconRoomHintsRepository(),
        RoomReadWatermarkStore.testing(),
        buildTestRealtimeSync().case_,
      ),
    );
  addTearDown(() {
    _unregister<BeaconFactCardRepository>();
    _unregister<BeaconThreadsCase>();
  });
}

/// The production GraphQL stack for one viewer; only HTTP is faked.
final class OriginWire {
  OriginWire._(this.remote, this.repository, this.sent);

  final RemoteApiService remote;
  final BeaconFactCardRepository repository;

  /// Operation names in the order the client sent them.
  final List<String> sent;

  /// [origin] is the BeaconFactCardOrigin row; [revisions] answers
  /// BeaconFactCardRevisions unless [revisionsResponse] supplies the full
  /// HTTP response body. In a widget test, call inside `tester.runAsync`.
  static Future<OriginWire> start({
    required Map<String, Object?> origin,
    List<Map<String, Object?>> revisions = const [],
    Map<String, Object?>? revisionsResponse,
  }) {
    final sent = <String>[];
    return http.runWithClient(
      () async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        await remote.setSessionAuth();
        // The GraphQL client is built here, inside the stubbed transport;
        // the session token is fetched lazily, so fetch it here as well.
        await remote.getAuthToken();
        return OriginWire._(remote, BeaconFactCardRepository(remote), sent);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return _json({
            'subject': 'Uviewer000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final name = body['operationName'] as String;
        sent.add(name);
        if (name == 'BeaconFactCardRevisions' && revisionsResponse != null) {
          return _json(revisionsResponse);
        }
        return _json({
          'data': switch (name) {
            'BeaconFactCardOrigin' => {
              '__typename': 'query_root',
              'BeaconFactCardOrigin': {
                '__typename': 'v2_BeaconFactCardOriginResult',
                ...origin,
              },
            },
            'BeaconFactCardRevisions' => {
              '__typename': 'query_root',
              'BeaconFactCardRevisions': {
                '__typename': 'v2_BeaconFactCardRevisionsPage',
                'entries': revisions,
                'nextCursor': null,
              },
            },
            _ => null,
          },
        });
      }),
    );
  }

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  Future<void> close() => remote.close();
}

/// A BeaconFactCardRevisions row for revision [seq] of the source fact.
Map<String, Object?> wireRevisionRow(int seq) => {
  '__typename': 'v2_BeaconFactHistoryEntryRow',
  'entry': 'revision',
  'entryKey': 'r${seq.toString().padLeft(10, '0')}',
  'id': null,
  'seq': seq,
  'kind': seq == 1 ? 0 : 1,
  'type': null,
  'factText': 'Revision text number $seq',
  'restoredFromSeq': null,
  'visibilityFrom': null,
  'visibilityTo': null,
  'actorId': 'U$seq',
  'actorTitle': revisionActor(seq),
  'createdAt': DateTime.utc(2026).add(Duration(minutes: seq)).toIso8601String(),
};

final class _Auth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'Uviewer000001');

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

final class _Settings extends Fake implements SettingsCubit {
  @override
  SettingsState get state => const SettingsState(introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();
}

/// Marker text on the copy's stub page.
const kCopyPageMarker = 'copy-page';

/// Pumps the real [RootRouter] starting at the copy's Request page.
///
/// The copy's page is a stub with an `open-copy` button running
/// [openCopy]. Any other Request page shows `source-page:<id>`, unless
/// [sourceScope] is given: then that Request mounts the real operational
/// route (and so the real Request screen) under [sourceScope].
Future<RootRouter> pumpOriginRouter(
  WidgetTester tester, {
  required void Function(BuildContext context) openCopy,
  Widget Function(Widget routerOutlet)? sourceScope,
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  final homePage = HomeRoute.page;
  final beaconPage = BeaconViewRoute.page;
  final operationalPage = BeaconViewOperationalRoute.page;
  addTearDown(() {
    HomeRoute.page = homePage;
    BeaconViewRoute.page = beaconPage;
    BeaconViewOperationalRoute.page = operationalPage;
  });
  // The browse stack keeps Home mounted below the Request.
  HomeRoute.page = PageInfo(
    HomeRoute.name,
    builder: (_) => const SizedBox.shrink(),
  );
  BeaconViewRoute.page = PageInfo(
    BeaconViewRoute.name,
    builder: (data) {
      final id =
          data.params.optString('id') ??
          data.inheritedPathParams.optString('id') ??
          '';
      if (id == kCopyBeaconId) {
        return Scaffold(
          body: Builder(
            builder: (ctx) => Column(
              children: [
                const Text(kCopyPageMarker),
                TextButton(
                  onPressed: () => openCopy(ctx),
                  child: const Text('open-copy'),
                ),
              ],
            ),
          ),
        );
      }
      final scope = sourceScope;
      if (scope != null) return scope(const AutoRouter());
      return Scaffold(body: Text('source-page:$id'));
    },
  );
  if (sourceScope == null) {
    BeaconViewOperationalRoute.page = PageInfo(
      BeaconViewOperationalRoute.name,
      builder: (_) => const SizedBox.shrink(),
    );
  }

  final router = RootRouter(
    Logger('FactOriginRouter'),
    _Auth(),
    _Settings(),
    PostJoinNavigationCubit(),
  );
  addTearDown(router.dispose);

  tester.binding.platformDispatcher.defaultRouteNameTestValue =
      '/beacon/view/$kCopyBeaconId';
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  // The view, not only the surface: MediaQuery (and so the window class
  // the Request screen lays out for) must see the same size.
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp.router(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      builder: (_, child) => TenturaResponsiveScope(child: child!),
      routerConfig: router.config(
        deepLinkBuilder: router.deepLinkBuilder,
        deepLinkTransformer: router.deepLinkTransformer,
        reevaluateListenable: router.reevaluateListenable,
        includePrefixMatches: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text(kCopyPageMarker), findsOneWidget);
  return router;
}

/// The router's current location.
Uri routerLocation(RootRouter router) =>
    Uri.parse(router.navigationHistory.urlState.url);

/// Taps [finder] and lets real-time work (HTTP over the wire) finish, with
/// bounded pumps only (the Request screen never settles).
Future<void> tapAndPumpRealAsync(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await pumpRealAsync(tester);
}

/// Bounded pumps interleaved with real time.
Future<void> pumpRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps an app with a button `open` that runs [open].
Future<void> pumpOpener(
  WidgetTester tester, {
  required void Function(BuildContext context) open,
  Locale locale = const Locale('en'),
  Size size = const Size(375, 812),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => open(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The ARB key whose English value is exactly [english], from
/// `l10n/app_en.arb` (tests run from packages/client).
String arbKeyFor(String english) {
  final en = _arb('l10n/app_en.arb');
  final keys = [
    for (final e in en.entries)
      if (!e.key.startsWith('@') && e.value == english) e.key,
  ];
  expect(keys, hasLength(1), reason: 'one app_en.arb entry reads «$english»');
  return keys.single;
}

/// The Russian ARB value for the entry whose English value is [english].
String russianFor(String english) {
  final ru = _arb('l10n/app_ru.arb')[arbKeyFor(english)];
  expect(ru, isA<String>(), reason: 'app_ru.arb translates «$english»');
  return ru! as String;
}

Map<String, Object?> _arb(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

final _cyrillic = RegExp('[А-Яа-яЁё]');
bool hasCyrillic(String s) => _cyrillic.hasMatch(s);

/// Every text rendered under [scope] (plain text of each RichText).
List<String> textsUnder(WidgetTester tester, Finder scope) => [
  for (final w in tester.widgetList<RichText>(
    find.descendant(of: scope, matching: find.byType(RichText)),
  ))
    if (w.text.toPlainText().trim().isNotEmpty) w.text.toPlainText().trim(),
];

/// The origin line(s) under [scope]: every rendered text that mentions
/// where the fact was brought from.
List<String> originLinesUnder(WidgetTester tester, Finder scope) => [
  for (final t in textsUnder(tester, scope))
    if (t.contains('Brought from') || t.contains(kOriginFromRequest)) t,
];

/// The history sheet's scrollable.
Finder historyScrollable() => find
    .descendant(
      of: find.byType(FactHistorySheet),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the history sheet until the row of revision [seq] is on screen.
Future<void> scrollToRevision(WidgetTester tester, int seq) async {
  final revision = find.textContaining(revisionActor(seq));
  final scrollable = historyScrollable();
  final position = tester.state<ScrollableState>(scrollable).position;

  while (revision.evaluate().isEmpty) {
    final before = position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scrollable),
        scrollDelta: Offset(0, position.viewportDimension),
      ),
    );
    await tester.pump();
    expect(
      position.pixels,
      greaterThan(before),
      reason: 'History stopped scrolling before reaching revision $seq',
    );
  }
  await tester.ensureVisible(revision);
}

/// Revisions whose history row is marked for assistive technology and on
/// screen: a semantics node in the selected state whose subtree (header and
/// body) names exactly one revision author. The copied revision is the
/// highlighted one, and its mark has to be perceivable, not only painted.
Set<int> selectedRevisions(WidgetTester tester) {
  final out = <int>{};
  final actor = RegExp(r'Actor-(\d+)-');
  String labels(SemanticsNode node) {
    final b = StringBuffer(node.label);
    node.visitChildren((c) {
      b.write(' ${labels(c)}');
      return true;
    });
    return b.toString();
  }

  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isSelected == Tristate.isTrue) {
      final seqs = actor
          .allMatches(labels(node))
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      if (seqs.length == 1) out.addAll(seqs);
    }
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return out;
}

/// Every Russian value whose English entry reads exactly [english] (for
/// words like «Open» that many entries share).
Set<String> russianValuesFor(String english) {
  final en = _arb('l10n/app_en.arb');
  final ru = _arb('l10n/app_ru.arb');
  return {
    for (final e in en.entries)
      if (!e.key.startsWith('@') && e.value == english && ru[e.key] is String)
        ru[e.key]! as String,
  };
}
