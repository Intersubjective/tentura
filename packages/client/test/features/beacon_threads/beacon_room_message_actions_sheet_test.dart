import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/design_system/components/tentura_avatar_stack.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit(this._state);

  final RoomState _state;

  String? lastUpdatePlanLine;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream<RoomState>.empty();

  @override
  Future<void> markReadToBottom() async {}

  @override
  Future<void> updatePlan(String currentLine) async {
    lastUpdatePlanLine = currentLine;
  }
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.empty();
}

// tentura-n59 landing gate acceptance (chat read receipts)

void main() {
  final getIt = GetIt.I;

  const viewer = Profile(id: 'me', displayName: 'Me');
  const author = Profile(id: 'other', displayName: 'Alex');

  final messageCreatedAt = DateTime.utc(2026, 6, 30, 12);

  BeaconParticipant roomParticipant({
    required String userId,
    required String displayName,
  }) =>
      BeaconParticipant(
        id: 'p-$userId',
        beaconId: 'b1',
        userId: userId,
        role: BeaconParticipantRoleBits.helper,
        status: 0,
        roomAccess: RoomAccessBits.admitted,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        userTitle: displayName,
      );

  RoomReadWatermark readWatermark(String userId, DateTime lastSeenAt) =>
      RoomReadWatermark(userId: userId, lastSeenAt: lastSeenAt);

  Finder avatarStackInMessageActionsSheet() => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TenturaAvatarStack),
      );

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<_MockRoomCubit> pumpRoom(
    WidgetTester tester, {
    required double width,
    List<RoomMessage>? messages,
    Map<String, RoomReadWatermark> readWatermarks = const {},
    bool readWatermarksLoaded = false,
    List<BeaconParticipant> participants = const [],
    bool participantsLoaded = false,
  }) async {
    final profileCubit = _MockProfileCubit(viewer);
    final presenceCubit = _MockPresenceCubit();
    final state = RoomState(
      beaconId: 'b1',
      myUserId: viewer.id,
      beaconStatus: BeaconStatus.open,
      readWatermarks: readWatermarks,
      readWatermarksLoaded: readWatermarksLoaded,
      participants: participants,
      participantsLoaded: participantsLoaded,
      messages:
          messages ??
          [
            RoomMessage(
              id: 'm1',
              beaconId: 'b1',
              authorId: author.id,
              author: author,
              body: 'Hello room',
              createdAt: messageCreatedAt,
            ),
          ],
    );
    final roomCubit = _MockRoomCubit(state);

    getIt.registerSingleton<ProfileCubit>(profileCubit);
    getIt.registerSingleton<ImageRepository>(ImageRepository());
    getIt.registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<RoomCubit>.value(value: roomCubit),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<PresenceCubit>.value(value: presenceCubit),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 900)),
            child: const TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconRoomBody(enableComposer: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return roomCubit;
  }

  // Center can land past the glyphs in the tucked-timestamp gap; use top-left.
  Future<void> longPressMessageBody(WidgetTester tester, Finder finder) =>
      tester.longPressAt(tester.getTopLeft(finder) + const Offset(8, 8));

  Future<double> openMessageActionsSheetWidth(WidgetTester tester) async {
    expect(find.byType(RoomMessageTile), findsOneWidget);
    final inlineBody = find.byType(RoomMessageTextBody);
    final body = inlineBody.evaluate().isNotEmpty
        ? inlineBody
        : find.byType(ShowMoreText);
    await longPressMessageBody(tester, body);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final scroller = find.descendant(
      of: sheet,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsOneWidget);

    return tester.getSize(scroller).width;
  }

  testWidgets('message actions sheet stays full-width on compact windows', (
    tester,
  ) async {
    await pumpRoom(tester, width: 375);

    expect(await openMessageActionsSheetWidth(tester), 375);
  });

  testWidgets('message actions sheet is width-capped on regular windows', (
    tester,
  ) async {
    await pumpRoom(tester, width: 700);

    expect(await openMessageActionsSheetWidth(tester), 560);
  });

  testWidgets('message actions sheet shows Reply for server messages', (
    tester,
  ) async {
    await pumpRoom(tester, width: 700);
    final l10n = lookupL10n(const Locale('en'));

    await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
  });

  testWidgets('message actions sheet hides Reply for local pending messages', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpRoom(
      tester,
      width: 700,
      messages: [
        RoomMessage(
          id: 'local:pending',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Sending…',
          createdAt: DateTime.utc(2026, 6, 30, 12),
        ),
      ],
    );

    await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconRoomActionReply), findsNothing);
  });

  testWidgets(
    'update plan from message opens NOW sheet without target picker',
    (tester) async {
      final l10n = lookupL10n(const Locale('en'));
      await pumpRoom(tester, width: 700);

      await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.beaconRoomActionUpdatePlanFromMessage));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomActionUpdatePlan), findsOneWidget);
      expect(find.text(l10n.beaconRoomNeedInfoPickTarget), findsNothing);
      expect(find.text('Hello room'), findsOneWidget);
    },
  );

  testWidgets(
    'update plan from message saves NOW line via updatePlan (no coordination item)',
    (tester) async {
      final l10n = lookupL10n(const Locale('en'));
      final roomCubit = await pumpRoom(tester, width: 700);

      await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.beaconRoomActionUpdatePlanFromMessage));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(roomCubit.lastUpdatePlanLine, 'Hello room');
    },
  );

  group('message actions Read by row', () {
    const ownBody = 'Own message for read-by actions';

    RoomMessage ownMessage({String id = 'own-read-actions'}) => RoomMessage(
          id: id,
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: ownBody,
          createdAt: messageCreatedAt,
        );

    Future<void> openMessageActions(WidgetTester tester) async {
      await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'own read message with four readers shows Read by row, three names, +1, avatars',
      (tester) async {
        final l10n = lookupL10n(const Locale('en'));
        const r1 = 'reader-1';
        const r2 = 'reader-2';
        const r3 = 'reader-3';
        const r4 = 'reader-4';
        final participants = [
          roomParticipant(userId: r1, displayName: 'Reader One'),
          roomParticipant(userId: r2, displayName: 'Reader Two'),
          roomParticipant(userId: r3, displayName: 'Reader Three'),
          roomParticipant(userId: r4, displayName: 'Reader Four'),
        ];
        final watermarks = {
          r1: readWatermark(r1, messageCreatedAt),
          r2: readWatermark(r2, messageCreatedAt.add(const Duration(minutes: 1))),
          r3: readWatermark(r3, messageCreatedAt.add(const Duration(minutes: 2))),
          r4: readWatermark(r4, messageCreatedAt.add(const Duration(minutes: 3))),
        };

        await pumpRoom(
          tester,
          width: 700,
          messages: [ownMessage()],
          readWatermarks: watermarks,
          readWatermarksLoaded: true,
          participants: participants,
          participantsLoaded: true,
        );

        await openMessageActions(tester);

        expect(find.text(l10n.beaconRoomReadByTitle), findsOneWidget);
        expect(
          find.text(
            'Reader Four, Reader Three, Reader Two, ${l10n.beaconRoomReadByMore(1)}',
          ),
          findsOneWidget,
        );
        expect(avatarStackInMessageActionsSheet(), findsOneWidget);
      },
    );

    testWidgets(
      'own sent message with no readers shows nobody-yet copy and no avatar stack',
      (tester) async {
        final l10n = lookupL10n(const Locale('en'));

        await pumpRoom(
          tester,
          width: 700,
          messages: [ownMessage()],
          readWatermarks: {
            viewer.id: readWatermark(viewer.id, messageCreatedAt),
          },
          readWatermarksLoaded: true,
          participants: [
            roomParticipant(userId: author.id, displayName: author.displayName),
          ],
          participantsLoaded: true,
        );

        await openMessageActions(tester);

        expect(find.text(l10n.beaconRoomReadByTitle), findsOneWidget);
        expect(find.text(l10n.beaconRoomReadByNobodyYet), findsOneWidget);
        expect(avatarStackInMessageActionsSheet(), findsNothing);
      },
    );

    testWidgets('own pending message omits Read by row', (tester) async {
      final l10n = lookupL10n(const Locale('en'));

      await pumpRoom(
        tester,
        width: 700,
        messages: [ownMessage(id: 'local:pending-read-by')],
        readWatermarks: {
          author.id: readWatermark(author.id, messageCreatedAt),
        },
        readWatermarksLoaded: true,
      );

      await openMessageActions(tester);

      expect(find.text(l10n.beaconRoomReadByTitle), findsNothing);
      expect(find.text(l10n.beaconRoomReadByNobodyYet), findsNothing);
    });

    testWidgets('peer message omits Read by row', (tester) async {
      final l10n = lookupL10n(const Locale('en'));

      await pumpRoom(
        tester,
        width: 700,
        messages: [
          RoomMessage(
            id: 'peer-msg',
            beaconId: 'b1',
            authorId: author.id,
            author: author,
            body: 'Peer body',
            createdAt: messageCreatedAt,
          ),
        ],
        readWatermarks: {
          viewer.id: readWatermark(viewer.id, messageCreatedAt),
        },
        readWatermarksLoaded: true,
      );

      await longPressMessageBody(tester, find.byType(RoomMessageTextBody));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomReadByTitle), findsNothing);
    });

    testWidgets(
      'tapping Read by row opens reader sheet listing all four readers',
      (tester) async {
        final l10n = lookupL10n(const Locale('en'));
        const r1 = 'reader-1';
        const r2 = 'reader-2';
        const r3 = 'reader-3';
        const r4 = 'reader-4';
        final participants = [
          roomParticipant(userId: r1, displayName: 'Reader One'),
          roomParticipant(userId: r2, displayName: 'Reader Two'),
          roomParticipant(userId: r3, displayName: 'Reader Three'),
          roomParticipant(userId: r4, displayName: 'Reader Four'),
        ];
        final watermarks = {
          r1: readWatermark(r1, messageCreatedAt),
          r2: readWatermark(r2, messageCreatedAt.add(const Duration(minutes: 1))),
          r3: readWatermark(r3, messageCreatedAt.add(const Duration(minutes: 2))),
          r4: readWatermark(r4, messageCreatedAt.add(const Duration(minutes: 3))),
        };

        await pumpRoom(
          tester,
          width: 700,
          messages: [ownMessage()],
          readWatermarks: watermarks,
          readWatermarksLoaded: true,
          participants: participants,
          participantsLoaded: true,
        );

        await openMessageActions(tester);

        await tester.tap(find.text(l10n.beaconRoomReadByTitle));
        await tester.pumpAndSettle();

        expect(find.text('Reader One'), findsOneWidget);
        expect(find.text('Reader Two'), findsOneWidget);
        expect(find.text('Reader Three'), findsOneWidget);
        expect(find.text('Reader Four'), findsOneWidget);
      },
    );
  });
}
