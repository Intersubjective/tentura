// Marker 20 (BeaconRoomSemanticMarker.factsBrought): the room line the
// server writes when someone brings facts in from another Request or Post.
// Payload: {factCardIds, count, originBeaconKind: 0|1|null, factText only
// when count == 1}. RoomMessageTile must render a centered line naming the
// author and the origin; one fact also shows the quoted text and opens the
// fact on tap; several facts show a count and nothing to open.
//
// Also covers the fact history sheet entry for a copied revision (kind 4).

import 'dart:convert';

import 'package:ferry/ferry.dart'
    show
        Client,
        FetchPolicy,
        Link,
        NextLink,
        OperationRequest,
        OperationResponse,
        OperationType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/service/remote_api_client/remote_api_client_web.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_history_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_provenance_line.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import 'support/room_body_harness.dart';

const _kBeaconId = 'b-facts-brought';
const _kFactId = 'fact-brought-1';
const _kFactText = 'Gate code 4411';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _bob = Profile(id: 'u-bob', displayName: 'Bob');

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

RoomMessage _broughtMessage({
  required int count,
  required int? originBeaconKind,
  List<String>? ids,
}) => RoomMessage(
  id: 'sys-brought-$count-$originBeaconKind',
  beaconId: _kBeaconId,
  authorId: _bob.id,
  author: _bob,
  body: '',
  createdAt: DateTime.utc(2026, 1, 3),
  semanticMarker: BeaconRoomSemanticMarker.factsBrought,
  systemPayloadJson: jsonEncode({
    'factCardIds':
        ids ?? [_kFactId, for (var i = 1; i < count; i++) '$_kFactId-$i'],
    'count': count,
    'originBeaconKind': originBeaconKind,
    if (count == 1) 'factText': _kFactText,
  }),
);

BeaconFactCard _fact({
  String id = _kFactId,
  String text = _kFactText,
  String pinnedByTitle = 'Bob',
}) => BeaconFactCard(
  id: id,
  beaconId: _kBeaconId,
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: _bob.id,
  pinnedByTitle: pinnedByTitle,
  createdAt: DateTime.utc(2026),
  status: BeaconFactCardStatusBits.active,
);

Widget _harness(
  RoomMessage message, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 900),
  RoomCubit? room,
}) {
  Widget tile = RoomMessageTile(
    message: message,
    myProfile: _viewer,
    onToggleReaction: (_, _) async {},
  );
  if (room != null) {
    tile = BlocProvider<RoomCubit>.value(value: room, child: tile);
  }
  return MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
    ],
    child: MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(body: tile),
        ),
      ),
    ),
  );
}

String _allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final r in tester.widgetList<RichText>(find.byType(RichText)))
    r.text.toPlainText(),
].join('\n');

/// The fact actions sheet is open for [factId]: its provenance line carries
/// that fact (label-independent, so renamed actions don't matter).
Finder _sheetFor(String factId) => find.byWidgetPredicate(
  (w) => w is FactProvenanceLine && w.fact.id == factId,
  description: 'fact actions sheet for $factId',
);

/// Any text on screen (Text or RichText) whose whole string matches [re].
bool _hasLine(WidgetTester tester, RegExp re) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final r in tester.widgetList<RichText>(find.byType(RichText)))
    r.text.toPlainText(),
].any((x) => re.hasMatch(x));

Future<void> _pump(
  WidgetTester tester,
  RoomMessage message, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 900),
  RoomCubit? room,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _harness(message, locale: locale, size: size, room: room),
  );
  await tester.pumpAndSettle();
}

// --- real-path transport helpers -------------------------------------

class _FakeLink extends Link {
  _FakeLink(this.response);
  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

final class _StubRemoteApiClient extends RemoteApiClient {
  _StubRemoteApiClient(this._client)
    : super(
        apiEndpointUrl: 'http://test/graphql',
        apiEndpointUrlV2: 'http://test/api/v2/graphql',
        authJwtExpiresIn: const Duration(hours: 1),
        requestTimeout: const Duration(minutes: 1),
        userAgent: 'test',
      );

  final Client _client;

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => _client.request(request);
}

BeaconThreadsRepository _repositoryFor(Link link) {
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  return BeaconThreadsRepository(
    _StubRemoteApiClient(
      Client(
        link: link,
        defaultFetchPolicies: const {
          OperationType.query: FetchPolicy.NoCache,
          OperationType.mutation: FetchPolicy.NoCache,
        },
      ),
    ),
    realtime.port,
  );
}

Map<String, dynamic> _transportRow({
  required int marker,
  required String payload,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': 'Mbrought00001',
  'beaconId': 'Bbeacon0000001',
  'authorId': 'Ubob000000001',
  'body': '',
  'createdAt': '2026-08-14T10:00:00.000Z',
  'editedAt': null,
  'semanticMarker': marker,
  'systemMessageKind': null,
  'linkedBlockerId': null,
  'linkedFactCardId': null,
  'linkedPollingId': null,
  'linkedItemId': null,
  'linkedEventKind': null,
  'linkedItemKind': null,
  'linkedItemStatus': null,
  'linkedItemTitle': null,
  'linkedItemBody': null,
  'linkedItemCreatorId': null,
  'linkedItemTargetPersonId': null,
  'linkedItemCreatedAt': null,
  'linkedItemUpdatedAt': null,
  'linkedItemLinkedMessageId': null,
  'linkedItemResolvedAt': null,
  'pollDataJson': null,
  'systemPayloadJson': payload,
  'authorTitle': 'Bob',
  'authorHasPicture': false,
  'authorPicHeight': 0,
  'authorPicWidth': 0,
  'authorBlurHash': '',
  'authorImageId': '',
  'reactionsJson': null,
  'myReaction': null,
  'reactorsJson': null,
  'attachmentsJson': '[]',
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': null,
};

// --- fact history sheet ---------------------------------------------

class _ServeEntriesRepository extends Fake implements BeaconFactCardRepository {
  _ServeEntriesRepository(this.entries);
  final List<BeaconFactTimelineEntry> entries;

  @override
  Future<BeaconFactHistoryPage> revisions({
    required String beaconId,
    required String factCardId,
    String? before,
  }) async => (entries: entries, nextCursor: null);
}

Future<void> _pumpHistory(
  WidgetTester tester,
  List<BeaconFactTimelineEntry> entries, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 900),
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
              onPressed: () => showFactHistorySheet(
                ctx,
                beaconId: _kBeaconId,
                factCardId: _kFactId,
                baseRevisionSeq: 1,
                canMutate: false,
                repository: _ServeEntriesRepository(entries),
              ),
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

/// Runs the real [BeaconFactCardRepository] over the real RemoteApiService
/// with only the HTTP transport stubbed, and returns the mapped history.
Future<List<BeaconFactTimelineEntry>> _fetchHistoryOverTransport(
  Map<String, dynamic> revisionsResponse,
) {
  return http.runWithClient(
    () async {
      final remote = RemoteApiService(
        const Env(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      try {
        await remote.setSessionAuth();
        final page = await BeaconFactCardRepository(remote).revisions(
          beaconId: _kBeaconId,
          factCardId: _kFactId,
        );
        return page.entries;
      } finally {
        await remote.close();
      }
    },
    () => MockClient((request) async {
      if (request.url.path.endsWith('/session/access-token')) {
        return http.Response(
          jsonEncode({
            'subject': 'Ueditor000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': revisionsResponse}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Map<String, dynamic> _revisionsPage(int kind) => {
  '__typename': 'query_root',
  'BeaconFactCardRevisions': {
    '__typename': 'v2_BeaconFactCardRevisionsPage',
    'entries': [
      {
        '__typename': 'v2_BeaconFactHistoryEntryRow',
        'entry': 'revision',
        'entryKey': 'r0000000001',
        'id': null,
        'seq': 1,
        'kind': kind,
        'type': null,
        'factText': _kFactText,
        'restoredFromSeq': null,
        'visibilityFrom': null,
        'visibilityTo': null,
        'actorId': 'u-bob',
        'actorTitle': 'Bob',
        'createdAt': '2026-09-01T08:00:00.000Z',
      },
    ],
    'nextCursor': null,
  },
};

BeaconFactHistoryCopied _copied() => BeaconFactHistoryCopied(
  id: 'rev-1',
  factCardId: _kFactId,
  seq: 1,
  factText: _kFactText,
  actorId: _bob.id,
  actorTitle: 'Bob',
  createdAt: DateTime.utc(2026),
);

void main() {
  group('facts-brought room line', () {
    testWidgets(
      'one fact from a Request names the origin and quotes the text',
      (tester) async {
        await _pump(tester, _broughtMessage(count: 1, originBeaconKind: 0));
        expect(
          find.text('Bob brought a fact from another Request'),
          findsOneWidget,
        );
        expect(find.text(_kFactText), findsOneWidget);
      },
    );

    testWidgets('one fact from a Post says Post', (tester) async {
      await _pump(tester, _broughtMessage(count: 1, originBeaconKind: 1));
      expect(find.text('Bob brought a fact from another Post'), findsOneWidget);
      expect(find.text(_kFactText), findsOneWidget);
    });

    testWidgets('one fact of unknown origin drops «from another…» but keeps '
        'the quote', (tester) async {
      await _pump(tester, _broughtMessage(count: 1, originBeaconKind: null));
      expect(find.text('Bob brought a fact'), findsOneWidget);
      expect(find.textContaining('another'), findsNothing);
      expect(find.text(_kFactText), findsOneWidget);
    });

    testWidgets('several facts from a Post show the count and no quote', (
      tester,
    ) async {
      await _pump(tester, _broughtMessage(count: 3, originBeaconKind: 1));
      expect(
        find.text('Bob brought 3 facts from another Post'),
        findsOneWidget,
      );
      expect(find.text(_kFactText), findsNothing);
    });

    testWidgets('several facts from a Request show the count and no quote', (
      tester,
    ) async {
      await _pump(tester, _broughtMessage(count: 3, originBeaconKind: 0));
      expect(
        find.text('Bob brought 3 facts from another Request'),
        findsOneWidget,
      );
      expect(find.text(_kFactText), findsNothing);
    });

    testWidgets('several facts of unknown origin drop «from another…»', (
      tester,
    ) async {
      await _pump(tester, _broughtMessage(count: 3, originBeaconKind: null));
      expect(find.text('Bob brought 3 facts'), findsOneWidget);
      expect(find.textContaining('another'), findsNothing);
    });

    for (final tapTarget in ['quote', 'line']) {
      testWidgets(
        'tapping the $tapTarget of the single-fact line opens the fact named '
        'by factCardIds[0], not another fact in the room',
        (tester) async {
          final room = RoomBodyHarnessCubit(
            roomBodyState().copyWith(
              beaconId: _kBeaconId,
              factCards: [
                _fact(
                  id: 'other-fact',
                  text: 'Other text',
                  pinnedByTitle: 'Yan',
                ),
                _fact(pinnedByTitle: 'Zed'),
              ],
            ),
          );
          await _pump(
            tester,
            _broughtMessage(count: 1, originBeaconKind: 0, ids: [_kFactId]),
            room: room,
          );
          expect(_sheetFor(_kFactId), findsNothing);

          await tester.tap(
            tapTarget == 'quote'
                ? find.text(_kFactText)
                : find.text('Bob brought a fact from another Request'),
          );
          await tester.pumpAndSettle();

          expect(_sheetFor(_kFactId), findsOneWidget);
          expect(_sheetFor('other-fact'), findsNothing);
        },
      );
    }

    testWidgets('tapping the several-facts line opens nothing', (tester) async {
      final room = RoomBodyHarnessCubit(
        roomBodyState().copyWith(beaconId: _kBeaconId, factCards: [_fact()]),
      );
      await _pump(
        tester,
        _broughtMessage(count: 3, originBeaconKind: 0),
        room: room,
      );

      await tester.tap(find.text('Bob brought 3 facts from another Request'));
      await tester.pumpAndSettle();

      expect(find.byType(FactProvenanceLine), findsNothing);
    });

    testWidgets('line comes through the real room-message transport mapper', (
      tester,
    ) async {
      final repo = _repositoryFor(
        _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'RoomMessageList': [
                _transportRow(
                  marker: 20,
                  payload: jsonEncode({
                    'factCardIds': [_kFactId],
                    'count': 1,
                    'originBeaconKind': 0,
                    'factText': _kFactText,
                  }),
                ),
              ],
            },
            response: const {},
          ),
        ),
      );
      final messages = await repo.fetchMessages(beaconId: 'Bbeacon0000001');
      expect(messages.single.semanticMarker, 20);

      await _pump(tester, messages.single);

      expect(
        find.text('Bob brought a fact from another Request'),
        findsOneWidget,
      );
      expect(find.text(_kFactText), findsOneWidget);
    });
  });

  group('facts-brought room line, Russian locale at 375x667', () {
    const ru = Locale('ru');
    const phone = Size(375, 667);

    Future<void> pumpRu(WidgetTester tester, int count, int? kind) async {
      await _pump(
        tester,
        _broughtMessage(count: count, originBeaconKind: kind),
        locale: ru,
        size: phone,
      );
      expect(tester.takeException(), isNull);
      expect(_allText(tester), isNot(contains('brought')));
    }

    Future<void> expectLine(
      WidgetTester tester,
      int count,
      int? kind,
      String tail,
    ) async {
      await pumpRu(tester, count, kind);
      expect(
        _hasLine(tester, RegExp('^Bob прин[её]с.*$tail\$')),
        isTrue,
        reason: _allText(tester),
      );
    }

    testWidgets('one fact from a Request, with the quote', (tester) async {
      await expectLine(tester, 1, 0, ' факт из другого запроса');
      expect(find.text(_kFactText), findsOneWidget);
    });

    testWidgets('one fact from a Post', (tester) async {
      await expectLine(tester, 1, 1, ' факт из другого поста');
    });

    testWidgets('one fact of unknown origin', (tester) async {
      await expectLine(tester, 1, null, ' факт');
    });

    testWidgets('3 facts use the «few» form', (tester) async {
      await expectLine(tester, 3, 0, ' 3 факта из другого запроса');
    });

    testWidgets('5 facts use the «many» form', (tester) async {
      await expectLine(tester, 5, 0, ' 5 фактов из другого запроса');
    });

    testWidgets('3 facts of unknown origin', (tester) async {
      await expectLine(tester, 3, null, ' 3 факта');
    });
  });

  group('fact history sheet, copied revision', () {
    testWidgets('a copied entry reads «Bob brought this here»', (tester) async {
      await _pumpHistory(tester, [_copied()]);
      expect(find.textContaining('Bob brought this here'), findsOneWidget);
    });

    testWidgets('a copied entry reads in Russian and fits 375x667', (
      tester,
    ) async {
      await _pumpHistory(
        tester,
        [_copied()],
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );
      final text = _allText(tester);
      expect(text, isNot(contains('brought')));
      expect(text, matches(RegExp('Bob прин[её]с.* сюда')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a history row of kind 4 over the real transport is a copied '
        'entry and the sheet shows «Bob brought this here»', (tester) async {
      final entries = (await tester.runAsync(
        () => _fetchHistoryOverTransport(_revisionsPage(4)),
      ))!;
      expect(entries.single, isA<BeaconFactHistoryCopied>());
      expect(entries.single, isNot(isA<BeaconFactHistoryCreated>()));

      await _pumpHistory(tester, entries);
      expect(find.textContaining('Bob brought this here'), findsOneWidget);
    });

    testWidgets('a created row (kind 0) over the real transport does not '
        'read as brought', (tester) async {
      final entries = (await tester.runAsync(
        () => _fetchHistoryOverTransport(_revisionsPage(0)),
      ))!;
      await _pumpHistory(tester, entries);
      expect(find.textContaining('brought'), findsNothing);
    });
  });
}
