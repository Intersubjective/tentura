// The Post info sheet's «Facts» section offers «Add fact» (New fact / Pick
// from available) when the Post's Chat is writable: the section and button
// show even with no facts, a pick copies a saved fact into the Post, a new
// fact is pinned through the composer without a visibility choice, and the
// list refreshes after both. An archived or read-only Post shows no button.
//
// Real path: HTTP (fact list / saved list / copy / pin operations) -> Ferry
// -> the real BeaconFactCardRepository mapper -> real RoomCubit ->
// PostInfoSheet. Only the transport and the room-message repository are fakes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:get_it/get_it.dart';
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
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';
import 'package:tentura/features/post_view/ui/widget/post_info_sheet.dart';
import 'package:tentura/features/post_view/ui/widget/post_participants_list.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fact_origin_test_support.dart';
import '../beacon_threads/room_cubit_fakes.dart';

const _postId = 'Bpostinfo001';
const _viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Maria');
const _keyFact = 'Spare key under the third flowerpot';
const _glovesFact = 'Bring two pairs of work gloves';
const _savedText = 'Shed code 4471';
const _savedId = 'Fother0000001';
const _otherBeacon = 'Bother0000001';
const _newText = 'Meet at the north gate';

final _createdAt = DateTime.utc(2026, 11, 13, 12);
final _now = DateTime.utc(2026, 11, 14, 12);

/// What the fake backend answers; the pick and the pin mutate [rows].
class _Wire {
  _Wire(List<_Row> rows) : rows = List.of(rows);

  final List<_Row> rows;

  /// BeaconKind value of the Post/Request the saved fact comes from.
  int savedKind = 0;
  final operations = <String>[];
  Map<String, dynamic>? copyVars;
  Map<String, dynamic>? pinVars;
}

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

/// Opens the info sheet of a Post whose fact list answers `wire`.
Future<RoomCubit> _openInfoSheet(
  WidgetTester tester, {
  required _Wire wire,
  bool archived = false,
  bool readOnly = false,
  bool lobbyLocked = false,
  Locale locale = const Locale('en'),
  Size size = const Size(700, 900),
}) async {
  registerRoomCubitProfileCubit(_viewer.id);
  if (!GetIt.I.isRegistered<Logger>()) {
    GetIt.I.registerSingleton<Logger>(Logger('test'));
    addTearDown(() => GetIt.I.unregister<Logger>());
  }

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
        registerFactRepository(facts);
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
        final name = body['operationName'] as String;
        wire.operations.add(name);
        return json({
          'data': switch (name) {
            'BeaconFactCardList' => {
              '__typename': 'query_root',
              'BeaconFactCardList': wire.rows.map(_wireRow).toList(),
            },
            'BeaconFactCardSavedList' => {
              '__typename': 'query_root',
              'BeaconFactCardSavedList': [
                {
                  '__typename': 'v2_BeaconFactCardSavedRow',
                  'factCardId': _savedId,
                  'available': true,
                  'beaconId': _otherBeacon,
                  'beaconKind': wire.savedKind,
                  'factText': _savedText,
                  'attachmentsJson': '[]',
                },
              ],
            },
            'BeaconFactCardCopy' => () {
              wire.copyVars = body['variables'] as Map<String, dynamic>;
              wire.rows.add((
                id: 'Fcopied000001',
                text: _savedText,
                origin: wire.savedKind,
              ));
              return {
                '__typename': 'mutation_root',
                'BeaconFactCardCopy': {
                  '__typename': 'v2_BeaconFactCardCopyResult',
                  'factCardId': 'Fcopied000001',
                  'outcome': 'created',
                },
              };
            }(),
            'BeaconFactCardPin' => () {
              wire.pinVars = body['variables'] as Map<String, dynamic>;
              wire.rows.add((
                id: 'Fpinned000001',
                text: wire.pinVars!['factText'] as String,
                origin: null,
              ));
              return {
                '__typename': 'mutation_root',
                'BeaconFactCardPin': true,
              };
            }(),
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
    lobbyAccess: lobbyLocked
        ? const BeaconLobbyAccess(canRead: true, canPost: false)
        : null,
  );
  final host =
      ThreadHostCubit(
        beaconId: _postId,
        capabilities: const RoomCapabilities.post(),
        roomCubitFactory:
            ({
              required beaconId,
              threadItemId,
              initialUnreadAnchorAt,
              capabilities = const RoomCapabilities.request(),
            }) => room,
      )..syncBeaconStatus(
        readOnly ? BeaconStatus.closed : BeaconStatus.open,
        authorId: _viewer.id,
      );
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
    wire.rows.map((r) => r.text),
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

final _addButton = find.byKey(TestIds.key(TestIds.beaconFactsAdd));
final _newItem = find.byKey(TestIds.key(TestIds.beaconFactsAddNew));
final _pickItem = find.byKey(TestIds.key(TestIds.beaconFactsAddPick));

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_addButton);
  await _settle(tester);
}

/// The wire answers asynchronously: let real time pass between pumps.
Future<void> _settleLong(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await _settle(tester);
  }
}

void main() {
  group('«Add fact» in the Facts section of the Post info sheet', () {
    testWidgets('a writable Post with no facts shows the «Facts» heading and '
        'one «Add fact» button', (tester) async {
      await _openInfoSheet(tester, wire: _Wire(const []));

      expect(_inSheet(find.text('Facts')), findsOneWidget);
      expect(_inSheet(_addButton), findsOneWidget);
      expect(_inSheet(find.text('Add fact')), findsOneWidget);
      expect(_inSheet(find.byType(BeaconPinnedFactCard)), findsNothing);
    });

    testWidgets('a writable Post lists its facts in order with the button '
        'below the list', (tester) async {
      await _openInfoSheet(
        tester,
        wire: _Wire(const [
          (id: 'Ffact0000001', text: _keyFact, origin: null),
          (id: 'Ffact0000002', text: _glovesFact, origin: null),
        ]),
      );

      final tops = [
        tester.getTopLeft(_inSheet(find.text(_keyFact))).dy,
        tester.getTopLeft(_inSheet(find.text(_glovesFact))).dy,
        tester.getTopLeft(_inSheet(_addButton)).dy,
      ];
      expect(_inSheet(find.text('Facts')), findsOneWidget);
      expect(tops[0], lessThan(tops[1]));
      expect(tops[1], lessThan(tops[2]));
    });

    testWidgets('«Add fact» opens a menu with «New fact» and «Pick from '
        'available»', (tester) async {
      await _openInfoSheet(tester, wire: _Wire(const []));

      await _openMenu(tester);

      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(
        find.descendant(of: _newItem, matching: find.text('New fact')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _pickItem,
          matching: find.text('Pick from available'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Pick from available» opens the picker on Saved and All my '
        'facts, without an «In this Post» scope', (tester) async {
      await _openInfoSheet(tester, wire: _Wire(const []));

      await _openMenu(tester);
      await tester.tap(_pickItem);
      await _settleLong(tester);

      expect(find.byType(FactPickerSheet), findsOneWidget);
      final tabs = tester.widget<TenturaUnderlineTabs>(
        find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.byType(TenturaUnderlineTabs),
        ),
      );
      expect(tabs.tabs, hasLength(2));
      expect(tabs.tabs[0], contains('Saved'));
      expect(tabs.tabs[1], 'All my facts');
      expect(find.text('In this Post'), findsNothing);
    });

    testWidgets('picking a saved fact copies it into the Post and the section '
        'lists it with its origin line', (tester) async {
      final wire = _Wire(const [
        (id: 'Ffact0000001', text: _keyFact, origin: null),
      ]);
      await _openInfoSheet(tester, wire: wire);
      expect(_inSheet(find.text(_savedText)), findsNothing);

      final listCallsBefore = wire.operations
          .where((o) => o == 'BeaconFactCardList')
          .length;

      await _openMenu(tester);
      await tester.tap(_pickItem);
      await _settleLong(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.text(_savedText),
        ),
      );
      await _settleLong(tester);

      expect(wire.copyVars?['sourceFactCardId'], _savedId);
      expect(wire.copyVars?['destinationBeaconId'], _postId);
      expect(
        wire.operations.where((o) => o == 'BeaconFactCardList').length,
        greaterThan(listCallsBefore),
        reason: 'the section re-fetched the fact list after the copy',
      );
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(find.text('Fact added', findRichText: true), findsOneWidget);
      expect(_inSheet(find.text(_savedText)), findsOneWidget);
      expect(_inSheet(find.text(_keyFact)), findsOneWidget);
      expect(
        _inSheet(find.text('Brought from another Request')),
        findsOneWidget,
      );
    });

    testWidgets('«New fact» opens the composer without a visibility choice', (
      tester,
    ) async {
      await _openInfoSheet(tester, wire: _Wire(const []));

      await _openMenu(tester);
      await tester.tap(_newItem);
      await _settleLong(tester);

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
      expect(find.text('Make public'), findsNothing);
      expect(find.text('Discussion only'), findsNothing);
      expect(find.byType(RadioListTile<int>), findsNothing);
      expect(find.byType(Radio<int>), findsNothing);
      expect(find.byType(RadioGroup<int>), findsNothing);
    });

    testWidgets('submitting the composer pins the fact and the section lists '
        'it', (tester) async {
      final wire = _Wire(const []);
      await _openInfoSheet(tester, wire: wire);
      final listCallsBefore = wire.operations
          .where((o) => o == 'BeaconFactCardList')
          .length;

      await _openMenu(tester);
      await tester.tap(_newItem);
      await _settleLong(tester);
      await tester.enterText(find.byType(TextField), _newText);
      await tester.pump();
      await tester.tap(
        find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit)),
      );
      await _settleLong(tester);

      expect(wire.pinVars?['beaconId'], _postId);
      expect(wire.pinVars?['factText'], _newText);
      expect(_inSheet(find.text('Facts')), findsOneWidget);
      expect(_inSheet(find.text(_newText)), findsOneWidget);
      expect(
        wire.operations.where((o) => o == 'BeaconFactCardList').length,
        greaterThan(listCallsBefore),
        reason: 'the section re-fetched the fact list after the pin',
      );
    });

    testWidgets('picking a saved fact from another Post shows «Brought from '
        'another Post»', (tester) async {
      final wire = _Wire(const [])..savedKind = BeaconKind.post.value;
      await _openInfoSheet(tester, wire: wire);

      await _openMenu(tester);
      await tester.tap(_pickItem);
      await _settleLong(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.text(_savedText),
        ),
      );
      await _settleLong(tester);

      expect(wire.copyVars?['destinationBeaconId'], _postId);
      expect(_inSheet(find.text(_savedText)), findsOneWidget);
      expect(_inSheet(find.text('Brought from another Post')), findsOneWidget);
    });

    for (final dismiss in ['Cancel button', 'tap outside']) {
      for (final withFact in [false, true]) {
        testWidgets('closing the composer with the $dismiss on a Post with '
            '${withFact ? 'one fact keeps that fact' : 'no facts keeps the '
                      'heading and the button, no rows'}', (tester) async {
          final wire = _Wire([
            if (withFact) (id: 'Ffact0000001', text: _keyFact, origin: null),
          ]);
          await _openInfoSheet(tester, wire: wire);

          await _openMenu(tester);
          await tester.tap(_newItem);
          await _settleLong(tester);
          final l10n = await L10n.delegate.load(const Locale('en'));
          expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
          if (dismiss == 'Cancel button') {
            await tester.tap(find.text('Cancel'));
          } else {
            await tester.tapAt(const Offset(3, 3));
          }
          await _settleLong(tester);

          expect(find.text(l10n.beaconFactsComposerTitle), findsNothing);
          expect(wire.pinVars, isNull);
          expect(find.byType(PostInfoSheet), findsOneWidget);
          expect(_inSheet(find.text('Facts')), findsOneWidget);
          expect(_inSheet(_addButton), findsOneWidget);
          expect(
            _inSheet(find.byType(BeaconPinnedFactCard)),
            findsNWidgets(withFact ? 1 : 0),
          );
          if (withFact) expect(_inSheet(find.text(_keyFact)), findsOneWidget);
        });
      }
    }
  });

  group('«Add fact» is absent where the Post cannot be written to', () {
    for (final mode in ['archived', 'closed status', 'locked Chat']) {
      Future<void> open(WidgetTester tester, List<_Row> rows) => _openInfoSheet(
        tester,
        wire: _Wire(rows),
        archived: mode == 'archived',
        readOnly: mode == 'closed status',
        lobbyLocked: mode == 'locked Chat',
      );

      testWidgets('a $mode Post with no facts shows no section and no '
          'button, but the header, quick actions and participants render', (
        tester,
      ) async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        await open(tester, const []);

        expect(_inSheet(find.text('Facts')), findsNothing);
        expect(_inSheet(_addButton), findsNothing);
        expect(_inSheet(find.byType(BeaconPinnedFactCard)), findsNothing);
        expect(_inSheet(find.text('Maria')), findsWidgets);
        for (final label in [
          l10n.postInfoActionMute,
          l10n.postInfoActionPin,
          l10n.postInfoActionField,
        ]) {
          expect(_inSheet(find.text(label)), findsOneWidget, reason: label);
        }
        expect(
          find.descendant(
            of: find.byKey(PostInfoSheet.participantsKey),
            matching: find.byType(PostParticipantsList),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a $mode Post lists its facts without the button', (
        tester,
      ) async {
        await open(tester, const [
          (id: 'Ffact0000001', text: _keyFact, origin: null),
        ]);

        expect(_inSheet(find.text('Facts')), findsOneWidget);
        expect(_inSheet(find.text(_keyFact)), findsOneWidget);
        expect(_inSheet(_addButton), findsNothing);
        expect(find.byType(MenuItemButton), findsNothing);
      });
    }

    testWidgets('tapping a fact row of an archived Post opens the Post-mode '
        'fact actions', (tester) async {
      await _openInfoSheet(
        tester,
        wire: _Wire(const [
          (id: 'Ffact0000001', text: _keyFact, origin: null),
        ]),
        archived: true,
      );

      await tester.tap(_inSheet(find.text(_keyFact)));
      await _settleLong(tester);

      expect(find.text('Edit history'), findsOneWidget);
      expect(find.text('Use in another Request or Post'), findsOneWidget);
      expect(find.text('Copy text'), findsOneWidget);
      expect(_inSheet(_addButton), findsNothing);
    });
  });
}
