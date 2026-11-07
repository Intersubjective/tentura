// #1104: whitespace-only chat Send must be visibly disabled, not a silent no-op.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura/ui/widget/one_node_button.dart';

import '../../features/beacon_threads/room_cubit_fakes.dart';
import '../../features/beacon_threads/support/room_body_harness.dart';
import '../../features/beacon_threads/support/room_hint_wire_harness.dart';
import '../effect/fake_ui_effect_port.dart';
import '../../support/phone_surface.dart';

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

class _FakeImageRepository extends Fake implements ImageRepository {
  @override
  Future<List<ImagePicked>> pickMultipleImages() async => [];
}

class _PasteImageClipboard extends Fake implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      ClipboardImageReadResult.found(
        RoomPendingUpload(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'clip.png',
          mimeType: 'image/png',
        ),
      );
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

final _longWhitespace = '   \n\t  ${' '.padRight(120)}\n   \u00a0\u00a0   ';

final _quotedFact = BeaconFactCard(
  id: 'fact-1',
  beaconId: kRoomCubitFakeBeaconId,
  factText: 'The venue moved to 221B Baker Street',
  visibility: BeaconFactCardVisibilityBits.room,
  pinnedBy: 'peer-1',
  pinnedByTitle: 'Peer One',
  createdAt: DateTime.utc(2026, 6, 30, 12),
  status: BeaconFactCardStatusBits.active,
);

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

Finder _sendButton() => find.byKey(TestIds.key(TestIds.roomMessageSend));

Future<void> _pumpComposer(
  WidgetTester tester, {
  required Locale locale,
  Future<bool> Function(String body, List<RoomPendingUpload> uploads)? onSend,
  BeaconFactCard? pendingQuotedFact,
  ClipboardImageRepository? clipboardImageRepository,
  bool sendEnabled = true,
}) async {
  await usePhoneSurface(tester);

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconRoomComposer(
              imageRepository: _FakeImageRepository(),
              clipboardImageRepository:
                  clipboardImageRepository ?? _FakeClipboardImageRepository(),
              isSending: false,
              participants: const [],
              sendEnabled: sendEnabled,
              pendingQuotedFact: pendingQuotedFact,
              onSend: onSend ?? (_, _) async => true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _settleWire(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(
      BurstCoalescer.window + const Duration(milliseconds: 600),
    ),
  );
  await tester.pumpAndSettle();
}

BeaconParticipant _admitted(String userId, String title) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: kRoomCubitFakeBeaconId,
  userId: userId,
  userTitle: title,
  role: BeaconParticipantRoleBits.addressee,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<RoomOverRealHintWireRepository> _openWireRoom(
  WidgetTester tester, {
  required RoomHintWireServer server,
  required RoomCapabilities capabilities,
  required void Function(RoomOverRealHintWireRepository repo) onReady,
  RoomPostRootPin? postRoot,
}) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(roomHintWireViewerId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

  final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
  addTearDown(() => tester.runAsync(wire.close));

  final repo = RoomOverRealHintWireRepository(wire.repository)
    ..participants = [
      _admitted(roomHintWireViewerId, 'Мария'),
    ];
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = roomCubitForTest(
      repo,
      effects: FakeUiEffectPort(),
      realtimeSyncCase: RealtimeSyncCase(wire.realtime),
    );
    await awaitRoomCubitLoad(cubit);
    cubit.syncBeaconStatus(BeaconStatus.open);
  });
  addTearDown(() => tester.runAsync(cubit.close));

  const viewer = Profile(
    id: roomHintWireViewerId,
    displayName: 'Мария',
  );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(viewer),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconRoomBody(
              capabilities: capabilities,
              postRoot: postRoot,
            ),
          ),
        ),
      ),
    ),
  );
  await _settleWire(tester);
  onReady(repo);
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#1104 composer widget', () {
    testWidgets('RU 375×667: long whitespace-only text disables Send', (
      tester,
    ) async {
      final ru = lookupL10n(const Locale('ru'));
      var sendCalls = 0;

      await _pumpComposer(
        tester,
        locale: const Locale('ru'),
        onSend: (_, _) async {
          sendCalls++;
          return true;
        },
      );

      await tester.enterText(_composerField(), _longWhitespace);
      await tester.pump();

      final sendNode = tester.widget<OneNodeButton>(
        find.ancestor(
          of: _sendButton(),
          matching: find.byType(OneNodeButton),
        ),
      );
      expect(sendNode.enabled, isFalse);
      expect(
        tester.widget<IconButton>(_sendButton()).onPressed,
        isNull,
      );

      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();
      expect(sendCalls, 0);

      final sendSemantics = tester
          .getSemantics(find.byKey(TestIds.key(TestIds.roomMessageSend)))
          .getSemanticsData();
      expect(sendSemantics.label, ru.tooltipSendMessage);
      expect(sendSemantics.flagsCollection.isEnabled, isNot(isTrue));
    });

    testWidgets('non-blank text enables Send and delivers the body', (
      tester,
    ) async {
      String? sentBody;
      var sendCalls = 0;

      await _pumpComposer(
        tester,
        locale: const Locale('ru'),
        onSend: (body, _) async {
          sendCalls++;
          sentBody = body;
          return true;
        },
      );

      await tester.enterText(_composerField(), '  reply text  ');
      await tester.pump();
      expect(tester.widget<IconButton>(_sendButton()).onPressed, isNotNull);

      await tester.tap(_sendButton());
      await tester.pumpAndSettle();

      expect(sendCalls, 1);
      expect(sentBody, '  reply text  ');
    });

    testWidgets('quoted fact without text keeps Send enabled', (tester) async {
      var sendCalls = 0;

      await _pumpComposer(
        tester,
        locale: const Locale('ru'),
        pendingQuotedFact: _quotedFact,
        onSend: (_, _) async {
          sendCalls++;
          return true;
        },
      );

      expect(tester.widget<IconButton>(_sendButton()).onPressed, isNotNull);
      await tester.tap(_sendButton());
      await tester.pumpAndSettle();
      expect(sendCalls, 1);
    });

    testWidgets('attachment-only keeps Send enabled without visible text', (
      tester,
    ) async {
      var sendCalls = 0;

      await _pumpComposer(
        tester,
        locale: const Locale('ru'),
        clipboardImageRepository: _PasteImageClipboard(),
        onSend: (_, uploads) async {
          sendCalls++;
          expect(uploads, hasLength(1));
          return true;
        },
      );

      await tester.tap(find.byKey(const ValueKey('paste')));
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(_sendButton()).onPressed, isNotNull);
      await tester.tap(_sendButton());
      await tester.pumpAndSettle();
      expect(sendCalls, 1);
    });

    testWidgets('Enter without Shift does not send whitespace-only text', (
      tester,
    ) async {
      var sendCalls = 0;
      await _pumpComposer(
        tester,
        locale: const Locale('ru'),
        onSend: (_, _) async {
          sendCalls++;
          return true;
        },
      );
      await tester.enterText(_composerField(), _longWhitespace);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(sendCalls, 0);
    });
  });

  group('#1104 over wire-shaped room loads', () {
    late RoomHintWireServer server;

    setUp(() {
      server = RoomHintWireServer()
        ..messageRows = [
          roomHintWireMessageRow(
            id: 'Mroot0000001',
            authorId: 'Uauthor00001',
            authorTitle: 'Автор',
            createdAt: '2026-08-14T10:00:00.000Z',
            body: 'Корневое сообщение для чата',
          ),
        ];
    });

    testWidgets(
      'Request discussion: wire-mapped room, whitespace blocks send',
      (tester) async {
        RoomOverRealHintWireRepository? repo;

        await _openWireRoom(
          tester,
          server: server,
          capabilities: const RoomCapabilities.request(),
          onReady: (r) => repo = r,
        );

        await tester.enterText(_composerField(), _longWhitespace);
        await tester.pump();
        expect(tester.widget<IconButton>(_sendButton()).onPressed, isNull);

        await tester.tap(_sendButton(), warnIfMissed: false);
        await tester.pump();
        expect(repo!.createMessageCalls, 0);
        expect(server.queried, contains('RoomMessageList'));
      },
    );

    testWidgets('Post detail chat: wire-mapped room, whitespace blocks send', (
      tester,
    ) async {
      RoomOverRealHintWireRepository? repo;

      await _openWireRoom(
        tester,
        server: server,
        capabilities: const RoomCapabilities.post(),
        postRoot: const RoomPostRootPin(
          messageId: 'Mroot0000001',
          excerpt: 'Корневое сообщение для чата',
        ),
        onReady: (r) => repo = r,
      );

      await tester.enterText(_composerField(), '  \n  ');
      await tester.pump();
      expect(tester.widget<IconButton>(_sendButton()).onPressed, isNull);

      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();
      expect(repo!.createMessageCalls, 0);
    });
  });
}
