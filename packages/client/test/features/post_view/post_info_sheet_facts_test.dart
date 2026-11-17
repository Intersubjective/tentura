// The «Facts» section of a Post's info sheet (plan D17, R6, §6.6): the Post's
// only fact list. It lists the Post's facts in the order the fact list
// returns them, with the existing fact row and its origin line; a tap opens
// the existing fact actions sheet in its Post mode; it is hidden when the
// Post has no facts and stays on an archived Post.
//
// Real path: HTTP (BeaconFactCardList) -> Ferry -> the real
// BeaconFactCardRepository mapper -> the real BeaconThreadsCase -> a real
// RoomCubit -> PostInfoSheet. Only the transport and the room-message
// repository are fakes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_origin_line.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fact_sheet_feedback.dart';
import '../../support/phone_surface.dart';
import '../beacon_threads/fact_origin_test_support.dart' as origin;
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';

const _postId = 'Bpostinfo001';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Maria');
const _keyFact = 'Spare key under the third flowerpot';
const _glovesFact = 'Bring two pairs of work gloves';

final _createdAt = DateTime.utc(2026, 11, 13, 12);
final _now = DateTime.utc(2026, 11, 14, 12);

typedef _Row = ({String id, String text, int? origin});

/// Each fact has its own pinner, so a sheet opened for a fact can be told
/// from a sheet opened for another one.
String _pinnerOf(String factId) => factId == 'Ffact0000002' ? 'Boris' : 'Alice';

Map<String, Object?> _wireRow(_Row r) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': r.id,
  'beaconId': _postId,
  'factText': r.text,
  'visibility': BeaconFactCardVisibilityBits.room,
  'pinnedBy': _viewer.id,
  'pinnedByTitle': _pinnerOf(r.id),
  'sourceMessageId': null,
  'status': BeaconFactCardStatusBits.active,
  'createdAt': '2026-11-14T12:00:00.000Z',
  'updatedAt': null,
  'attachmentsJson': '[]',
  'revisionSeq': 1,
  'lastEditedBy': null,
  'lastEditedByTitle': null,
  'lastEditedAt': null,
  'otherEditorCount': 0,
  'historyTruncated': false,
  'savedByMe': false,
  'originBeaconKind': r.origin,
};

class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);

  final Beacon beacon;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Beacon _post({required bool archived}) => Beacon(
  id: _postId,
  kind: BeaconKind.post,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  expiresAt: archived
      ? _now.subtract(const Duration(hours: 1))
      : _now.add(const Duration(hours: 20)),
  author: _viewer,
  viewerCanForward: true,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the info sheet of a Post whose fact list answers [rows].
Future<RoomCubit> _openInfoSheet(
  WidgetTester tester, {
  required List<_Row> rows,
  bool archived = false,
  Locale locale = const Locale('en'),
  Size size = const Size(700, 900),
}) async {
  registerRoomCubitProfileCubit(_viewer.id);

  late RemoteApiService remote;
  late BeaconFactCardRepository facts;
  await tester.runAsync(() async {
    await http.runWithClient(
      () async {
        remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        await remote.setSessionAuth();
        await remote.getAuthToken();
        facts = BeaconFactCardRepository(remote);
      },
      () => MockClient((request) async {
        http.Response json(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/session/access-token')) {
          return json({
            'subject': _viewer.id,
            'access_token': 'test-token',
            'expires_in': 3600,
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return json({
          'data': switch (body['operationName']) {
            'BeaconFactCardList' => {
              '__typename': 'query_root',
              'BeaconFactCardList': rows.map(_wireRow).toList(),
            },
            _ => null,
          },
        });
      }),
    );
  });
  addTearDown(() => tester.runAsync(remote.close));

  final threads = FakeBeaconThreadsRepository(userId: _viewer.id);
  addTearDown(threads.dispose);
  final realtime = buildTestRealtimeSync();
  final roomCase = BeaconThreadsCase(
    threads,
    facts,
    FakePollingRepository(),
    FakeBeaconRoomHintsRepository(),
    RoomReadWatermarkStore.testing(),
    realtime.case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final room = RoomCubit(
    beaconId: _postId,
    beaconRoomCase: roomCase,
    coordinationItemRoomSync: CoordinationItemRoomSync(),
    presenceRepository: roomCubitFakePresenceRepository(),
    effects: FakeUiEffectPort(),
    capabilities: const RoomCapabilities.post(),
  );
  final host = ThreadHostCubit(
    beaconId: _postId,
    capabilities: const RoomCapabilities.post(),
    roomCubitFactory:
        ({
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          capabilities = const RoomCapabilities.request(),
        }) => room,
  )..syncBeaconStatus(BeaconStatus.open, authorId: _viewer.id);
  final cubit = PostViewCubit(
    id: _postId,
    myProfile: _viewer,
    beaconRepository: _PostRepository(_post(archived: archived)),
    effects: FakeUiEffectPort(),
    clock: () => _now,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await cubit.close();
    await host.close();
  });
  await tester.runAsync(cubit.fetch);
  await tester.runAsync(
    () => host.select(
      RequestThread(
        threadId: RequestThread.generalId,
        kind: RequestThreadKind.general,
        lastSeenAt: _createdAt,
      ),
    ),
  );
  await _settle(tester);
  expect(
    room.state.factCards.map((f) => f.factText),
    rows.map((r) => r.text),
    reason: 'the real fact list reached the Post room',
  );
  if (archived) room.syncBeaconExpired(true);

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => unawaited(
                  showPostInfoSheet(ctx, cubit: cubit, host: host),
                ),
                child: const Text('open-info'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-info'));
  await _settle(tester);
  expect(find.byType(PostInfoSheet), findsOneWidget);
  return room;
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(PostInfoSheet), matching: f);

const _two = <_Row>[
  (id: 'Ffact0000001', text: _keyFact, origin: null),
  (id: 'Ffact0000002', text: _glovesFact, origin: null),
];

void main() {
  testWidgets(
    'phone feedback exposes an unavailable origin in Post info pinned facts',
    (tester) async {
      origin.registerFactRepository(origin.FakeOriginFactCardRepository());
      await _openInfoSheet(
        tester,
        size: kPhoneSurface,
        rows: [(id: 'Ffact0000001', text: _keyFact, origin: 0)],
      );
      await tester.ensureVisible(find.byType(FactOriginLine));
      await tester.tap(find.byType(FactOriginLine));
      await tester.pumpAndSettle();
      expectPhoneFeedback(tester, "The original isn't available to you");
    },
  );


  group('Facts section of the Post info sheet', () {
    testWidgets('lists the Post facts top to bottom in list order, each as '
        'the existing fact row, under a «Facts» heading', (tester) async {
      final room = await _openInfoSheet(tester, rows: _two);

      expect(_inSheet(find.text('Facts')), findsOneWidget);
      // The rows are the facts the real repository delivered to the room,
      // in that order.
      final texts = room.state.factCards.map((f) => f.factText).toList();
      expect(texts, [_keyFact, _glovesFact]);
      expect(_inSheet(find.byType(BeaconPinnedFactCard)), findsNWidgets(2));
      final tops = [
        for (final t in texts) tester.getTopLeft(_inSheet(find.text(t))).dy,
      ];
      expect(tops[0], lessThan(tops[1]));
    });

    testWidgets('is absent when an archived Post has no facts; the author header, '
        'forwarding line, quick actions and participants still render', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _openInfoSheet(tester, rows: const [], archived: true);

      expect(_inSheet(find.text('Facts')), findsNothing);
      expect(_inSheet(find.byType(BeaconPinnedFactCard)), findsNothing);
      expect(
        _inSheet(find.text('Maria')),
        findsWidgets,
        reason: 'author header',
      );
      expect(
        _inSheet(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                (w.data == l10n.postInfoForwardingOpen ||
                    w.data == l10n.postInfoForwardingClosed),
          ),
        ),
        findsOneWidget,
      );
      for (final label in [
        l10n.postInfoActionMute,
        l10n.postInfoActionPin,
        l10n.postInfoActionField,
      ]) {
        expect(
          _inSheet(find.text(label)),
          findsOneWidget,
          reason: 'quick action «$label»',
        );
      }
      expect(
        find.descendant(
          of: find.byKey(PostInfoSheet.participantsKey),
          matching: find.byType(PostParticipantsList),
        ),
        findsOneWidget,
      );
    });

    test(
      'the «Facts» heading has English and Russian ARB entries under one key',
      () {
        Map<String, dynamic> arb(String lang) =>
            jsonDecode(File('l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        final en = arb('en');
        final ru = arb('ru');
        final keys = en.entries
            .where((e) => e.value == 'Facts' && !e.key.startsWith('@'))
            .map((e) => e.key)
            .toList();
        expect(keys, isNotEmpty, reason: 'app_en.arb has a «Facts» entry');
        expect(
          keys.any((k) => ru[k] == 'Факты'),
          isTrue,
          reason: 'app_ru.arb has «Факты» under the same key',
        );
      },
    );

    testWidgets('a copied fact shows its origin line, an own fact none', (
      tester,
    ) async {
      await _openInfoSheet(
        tester,
        rows: [
          (id: 'Ffact0000001', text: _keyFact, origin: null),
          (
            id: 'Ffact0000002',
            text: _glovesFact,
            origin: BeaconKind.post.value,
          ),
          (
            id: 'Ffact0000003',
            text: 'Ladder',
            origin: BeaconKind.request.value,
          ),
        ],
      );

      Finder originOf(String text) => find.descendant(
        of: find.ancestor(
          of: _inSheet(find.text(text)),
          matching: find.byType(BeaconPinnedFactCard),
        ),
        matching: find.byType(FactOriginLine),
      );
      expect(_inSheet(find.text(_keyFact)), findsOneWidget);
      // The shared fact row always builds FactOriginLine; for an own fact it
      // renders nothing.
      expect(
        find.descendant(of: originOf(_keyFact), matching: find.byType(Text)),
        findsNothing,
        reason: 'own fact: no line',
      );
      for (final body in [_glovesFact, 'Ladder']) {
        expect(
          find.descendant(of: originOf(body), matching: find.byType(Text)),
          findsOneWidget,
          reason: 'copied fact «$body» shows its origin line',
        );
      }
      expect(_inSheet(find.text('Brought from another Post')), findsOneWidget);
      expect(
        _inSheet(find.text('Brought from another Request')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row of a live Post opens the Post-mode fact '
        'actions: no public / private choice', (tester) async {
      await _openInfoSheet(tester, rows: _two);

      await tester.tap(_inSheet(find.text(_glovesFact)));
      await _settle(tester);

      final l10n = await L10n.delegate.load(const Locale('en'));
      final sheet = find.ancestor(
        of: find.text(l10n.beaconRoomFactManageSheetTitle),
        matching: find.byType(SingleChildScrollView),
      );
      expect(sheet, findsWidgets);
      expect(
        find.descendant(
          of: sheet.first,
          matching: find.textContaining('Boris'),
        ),
        findsOneWidget,
        reason: 'the sheet is for the tapped fact (pinned by Boris)',
      );
      expect(
        find.descendant(
          of: sheet.first,
          matching: find.textContaining('Alice'),
        ),
        findsNothing,
      );
      expect(find.text('Use in another Request or Post'), findsOneWidget);
      expect(find.text('Make public'), findsNothing);
      expect(find.text('Discussion only'), findsNothing);
    });

    testWidgets('an archived Post still lists its facts; a row opens '
        'History, Use elsewhere and Copy text, no Edit or Unpin', (
      tester,
    ) async {
      await _openInfoSheet(tester, rows: _two, archived: true);

      expect(_inSheet(find.text('Facts')), findsOneWidget);
      expect(_inSheet(find.text(_keyFact)), findsOneWidget);
      expect(_inSheet(find.text(_glovesFact)), findsOneWidget);

      await tester.tap(_inSheet(find.text(_keyFact)));
      await _settle(tester);

      expect(find.text('Edit history'), findsOneWidget);
      expect(find.text('Use in another Request or Post'), findsOneWidget);
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Edit text'), findsNothing);
      expect(find.text('Unpin'), findsNothing);
    });

    testWidgets('reads «Факты» in Russian at 375x667 without overflow, '
        'origin line included', (tester) async {
      await _openInfoSheet(
        tester,
        rows: [
          (id: 'Ffact0000001', text: _keyFact, origin: null),
          (
            id: 'Ffact0000002',
            text: _glovesFact,
            origin: BeaconKind.post.value,
          ),
          (
            id: 'Ffact0000003',
            text: 'Ladder',
            origin: BeaconKind.request.value,
          ),
        ],
        locale: const Locale('ru'),
        size: const Size(375, 667),
      );

      expect(_inSheet(find.text('Факты')), findsOneWidget);
      for (final body in [_keyFact, _glovesFact, 'Ladder']) {
        final f = _inSheet(find.text(body));
        expect(f, findsOneWidget, reason: 'fact row «$body»');
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(0), reason: body);
        expect(r.right, lessThanOrEqualTo(375), reason: body);
      }
      expect(_inSheet(find.text('Принесён из другого поста')), findsOneWidget);
      expect(
        _inSheet(find.text('Принесён из другого запроса')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
