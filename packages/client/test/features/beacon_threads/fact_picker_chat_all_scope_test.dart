// The chat composer's «Fact» item in a Request chat and in a Post chat opens
// the one fact picker with all three scopes — «In this Request» / «In this
// Post», «Saved» and «All my facts». A fact from another episode picked from
// «All my facts» is copied into this chat's own Request or Post, the copy is
// quoted in the composer and the composer gets keyboard focus. The Questions
// lobby offers no «Fact» item at all.
//
// Reached the way a person reaches it: `BeaconRoomBody` over a real
// RoomCubit and the real BeaconThreadsCase and BeaconFactCardRepository over
// the real RemoteApiService; only the HTTP transport is stubbed. Search and
// copy answers travel the real GraphQL mapper.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../support/test_realtime_sync.dart';
import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

const _otherBeacon = 'Bother0000001';
const _hitId = 'Fhit000000001';
const _hitText = 'Gate code is 4711';
const _copyId = 'Fcopy00000001';

final _en = lookupL10n(const Locale('en'));
const _tabAll = 'All my facts';

/// The stubbed server: serves the room's fact list (the copy appears there
/// once copied), one search hit and the copy mutation.
final class _Wire {
  _Wire._(this.remote, this.repository);

  final RemoteApiService remote;
  final BeaconFactCardRepository repository;

  /// Variables of every BeaconFactCardCopy sent.
  final copies = <Map<String, dynamic>>[];
  final searches = <Map<String, dynamic>>[];
  final _copied = false;

  static Future<_Wire> start() async {
    _Wire? wire;
    final copies = <Map<String, dynamic>>[];
    final searches = <Map<String, dynamic>>[];
    var copied = false;
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final made = await http.runWithClient(
      () async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        await remote.setSessionAuth();
        await remote.getAuthToken();
        return _Wire._(remote, BeaconFactCardRepository(remote));
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return json({
            'subject': 'Uviewer000001',
            'access_token': 'test-token',
            'expires_in': 3600,
          });
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final vars = ((body['variables'] ?? <String, dynamic>{}) as Map)
            .cast<String, dynamic>();
        final name = body['operationName'] as String;
        return json({
          'data': switch (name) {
            'BeaconFactCardList' => {
              '__typename': 'query_root',
              'BeaconFactCardList': [
                if (copied)
                  _factRow(_copyId, _hitText, vars['beaconId'] as String),
              ],
            },
            'BeaconFactCardSavedList' => {
              '__typename': 'query_root',
              'BeaconFactCardSavedList': <Object?>[],
            },
            'BeaconFactCardSearch' => () {
              searches.add(vars);
              return {
                '__typename': 'query_root',
                'BeaconFactCardSearch': [
                  {
                    '__typename': 'v2_BeaconFactCardSearchRow',
                    'factCardId': _hitId,
                    'beaconId': _otherBeacon,
                    'beaconKind': 0,
                    'factText': _hitText,
                    'attachmentsJson': '[]',
                    'saved': false,
                  },
                ],
              };
            }(),
            'BeaconFactCardCopy' => () {
              copies.add(vars);
              copied = true;
              return {
                '__typename': 'mutation_root',
                'BeaconFactCardCopy': {
                  '__typename': 'v2_BeaconFactCardCopyResult',
                  'factCardId': _copyId,
                  'outcome': 'created',
                },
              };
            }(),
            _ => null,
          },
        });
      }),
    );
    wire = made;
    wire.copies.addAll(const []);
    // Share the recording lists with the closure above.
    wire._bind(copies, searches, () => copied);
    return wire;
  }

  List<Map<String, dynamic>>? _copiesRef;

  void _bind(
    List<Map<String, dynamic>> c,
    List<Map<String, dynamic>> s,
    bool Function() copied,
  ) {
    _copiesRef = c;
    _searchesRef = s;
    _copiedRef = copied;
  }

  List<Map<String, dynamic>>? _searchesRef;
  bool Function()? _copiedRef;

  List<Map<String, dynamic>> get copyCalls => _copiesRef ?? copies;
  List<Map<String, dynamic>> get searchCalls => _searchesRef ?? searches;
  bool get hasCopied => _copiedRef?.call() ?? _copied;

  Future<void> close() => remote.close();
}

Map<String, dynamic> _factRow(String id, String text, String beaconId) => {
  '__typename': 'v2_BeaconFactCardRow',
  'id': id,
  'beaconId': beaconId,
  'factText': text,
  'visibility': 0,
  'pinnedBy': 'Uviewer000001',
  'pinnedByTitle': 'Me',
  'sourceMessageId': null,
  'status': 0,
  'createdAt': '2026-09-01T08:00:00.000Z',
  'updatedAt': null,
  'attachmentsJson': '[]',
  'revisionSeq': 1,
  'lastEditedBy': null,
  'lastEditedByTitle': null,
  'lastEditedAt': null,
  'otherEditorCount': 0,
  'historyTruncated': false,
  'originBeaconKind': 0,
  'savedByMe': false,
};

class _Room {
  _Room(this.cubit, this.wire);

  final RoomCubit cubit;
  final _Wire wire;
}

/// Pumps [BeaconRoomBody] over a real [RoomCubit] whose fact repository is
/// the real one over the stubbed transport.
Future<_Room> _pumpRoom(
  WidgetTester tester, {
  RoomCapabilities capabilities = const RoomCapabilities.request(),
  Locale locale = const Locale('en'),
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  if (!getIt.isRegistered<Logger>()) {
    getIt.registerSingleton<Logger>(Logger('test'));
  }
  const viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Me');
  final profileCubit = RoomBodyHarnessProfileCubit(viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  addTearDown(getIt.reset);

  final fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  addTearDown(fakeRoom.dispose);

  final (wire, cubit) = (await tester.runAsync(() async {
    final wire = await _Wire.start();
    final threadsCase = BeaconThreadsCase(
      fakeRoom,
      wire.repository,
      FakePollingRepository(),
      FakeBeaconRoomHintsRepository(),
      RoomReadWatermarkStore.testing(),
      buildTestRealtimeSync().case_,
    );
    final cubit = roomCubitForTest(fakeRoom, beaconRoomCase: threadsCase);
    await awaitRoomCubitLoad(cubit);
    cubit.syncBeaconStatus(BeaconStatus.open);
    return (wire, cubit);
  }))!;
  addTearDown(cubit.close);
  addTearDown(wire.close);

  const size = Size(390, 812);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: RoomBodyHarnessPresenceCubit()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(body: BeaconRoomBody(capabilities: capabilities)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return _Room(cubit, wire);
}

Future<void> _openFactPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('attach')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.beaconRoomAttachPickFact));
  await tester.pumpAndSettle();
  expect(find.byType(FactPickerSheet), findsOneWidget);
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(FactPickerSheet), matching: f);

TenturaUnderlineTabs _tabs(WidgetTester tester) =>
    tester.widget<TenturaUnderlineTabs>(
      _inSheet(find.byType(TenturaUnderlineTabs)),
    );

/// The tab labels, read from the visible tab row in order.
List<String> _tabLabels(WidgetTester tester) {
  final row = _inSheet(find.byType(TenturaUnderlineTabs));
  final texts = tester.widgetList<Text>(
    find.descendant(of: row, matching: find.byType(Text)),
  );
  return [for (final t in texts) t.data ?? t.textSpan?.toPlainText() ?? ''];
}

Future<void> _pickFromAllMyFacts(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: _inSheet(find.byType(TenturaUnderlineTabs)),
      matching: find.textContaining(_tabAll),
    ),
  );
  await tester.pumpAndSettle();
  final search = _inSheet(
    find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search facts',
    ),
  );
  await tester.enterText(search, 'gate');
  await tester.pump(const Duration(milliseconds: 400));
  await pumpRealAsync(tester);
  await tester.pumpAndSettle();
  final hit = _inSheet(find.text(_hitText));
  expect(hit, findsOneWidget, reason: 'the search hit shows as a row');
  await tester.tap(hit);
  await pumpRealAsync(tester);
  await tester.pumpAndSettle();
}

void _expectComposerFocused(WidgetTester tester) {
  final field = find.descendant(
    of: find.byType(BasicChatBody),
    matching: find.byType(EditableText),
  );
  expect(field, findsWidgets);
  expect(
    tester.widgetList<EditableText>(field).any((e) => e.focusNode.hasFocus),
    isTrue,
    reason: 'the composer text field has keyboard focus after the pick',
  );
}

void main() {
  group('Request chat «Fact» picker', () {
    testWidgets('shows «In this Request», «Saved», «All my facts» in order, '
        'opening on the first', (tester) async {
      await _pumpRoom(tester);
      await _openFactPicker(tester);

      final labels = _tabLabels(tester);
      expect(labels, [
        _en.beaconRoomFactPickerTabRequest,
        _en.beaconRoomFactPickerTabSaved,
        _tabAll,
      ]);
      expect(_tabs(tester).selectedIndex, 0);
    });

    testWidgets('a hit from another episode is copied once into this Request, '
        'quoted, and the composer gets focus', (tester) async {
      final room = await _pumpRoom(tester);
      await _openFactPicker(tester);
      await _pickFromAllMyFacts(tester);

      expect(room.wire.copyCalls, hasLength(1));
      expect(room.wire.copyCalls.single, {
        'sourceFactCardId': _hitId,
        'destinationBeaconId': kRoomCubitFakeBeaconId,
      });
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(room.cubit.state.factCards.map((f) => f.id), contains(_copyId));
      final quoted = room.cubit.state.pendingQuotedFact;
      expect(quoted?.factCardId, _copyId);
      _expectComposerFocused(tester);
    });

    testWidgets('the picker words nothing as «beacon» or «room»', (
      tester,
    ) async {
      await _pumpRoom(tester);
      await _openFactPicker(tester);
      final words = [
        for (final t in tester.widgetList<Text>(
          _inSheet(find.byType(Text)),
        ))
          (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase(),
      ];
      expect(words, isNotEmpty);
      for (final w in words) {
        expect(w, isNot(contains('beacon')));
        expect(w, isNot(contains('room')));
      }
    });
  });

  group('Post chat «Fact» picker', () {
    testWidgets('shows «In this Post», «Saved», «All my facts» in order, no '
        '«In this Request»', (tester) async {
      await _pumpRoom(tester, capabilities: const RoomCapabilities.post());
      await _openFactPicker(tester);

      final labels = _tabLabels(tester);
      expect(labels, [
        _en.beaconRoomFactPickerTitlePost,
        _en.beaconRoomFactPickerTabSaved,
        _tabAll,
      ]);
      expect(labels, isNot(contains(_en.beaconRoomFactPickerTabRequest)));
      expect(_tabs(tester).selectedIndex, 0);
    });

    testWidgets('a hit from another episode is copied into this Post, quoted, '
        'and the composer gets focus', (tester) async {
      final room = await _pumpRoom(
        tester,
        capabilities: const RoomCapabilities.post(),
      );
      await _openFactPicker(tester);
      await _pickFromAllMyFacts(tester);

      expect(room.wire.copyCalls, hasLength(1));
      expect(room.wire.copyCalls.single['destinationBeaconId'],
          kRoomCubitFakeBeaconId);
      expect(find.byType(FactPickerSheet), findsNothing);
      expect(room.cubit.state.factCards.map((f) => f.id), contains(_copyId));
      expect(room.cubit.state.pendingQuotedFact?.factCardId, _copyId);
      _expectComposerFocused(tester);
    });

    testWidgets('the picker words nothing as «beacon» or «room»', (
      tester,
    ) async {
      await _pumpRoom(tester, capabilities: const RoomCapabilities.post());
      await _openFactPicker(tester);
      for (final t in tester.widgetList<Text>(_inSheet(find.byType(Text)))) {
        final w = (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase();
        expect(w, isNot(contains('beacon')));
        expect(w, isNot(contains('room')));
      }
    });
  });

  group('Questions lobby composer', () {
    testWidgets('offers no «Fact» item', (tester) async {
      await _pumpRoom(tester, capabilities: const RoomCapabilities.questions());
      expect(find.byType(FactPickerSheet), findsNothing);
      final attach = find.byKey(const ValueKey('attach'));
      if (attach.evaluate().isNotEmpty) {
        await tester.tap(attach);
        await tester.pumpAndSettle();
      }
      expect(find.text(_en.beaconRoomAttachPickFact), findsNothing);
    });
  });
}
