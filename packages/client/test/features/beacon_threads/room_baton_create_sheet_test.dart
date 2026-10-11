// «Who'll take it?» start flow in the room:
//  - the message-actions sheet offers «Who'll take it?» on anyone's plain
//    (or poll) message, not on system lines or baton messages, while the feature flag
//    is on and the room is writable (the flag is injected through
//    `BeaconRoomBody`); the baton is then posted as a new message replying to
//    that one;
//  - it is reachable by long-press and by secondary tap;
//  - the create sheet lists admitted room members (with avatars) except the
//    viewer, keeps «Ask» disabled unless 1–12 people are picked, shows
//    priority controls only after «Set priority» is switched on, and submits
//    the ask text, the reply target and `[{userId, tier}]` through
//    `RoomCubit.batonCreate`.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/enums.dart';

typedef _Candidate = ({String userId, int tier});

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit(this._state);

  final RoomState _state;

  final batonCreateCalls =
      <
        ({
          String text,
          String? replyToMessageId,
          List<_Candidate> candidates,
        })
      >[];

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => const Stream<RoomState>.empty();

  @override
  Future<void> markReadToBottom() async {}

  final batonUpdateCalls =
      <({String batonId, String text, List<_Candidate> candidates})>[];

  final batonCancelCalls = <String>[];

  @override
  Future<void> batonUpdate({
    required String batonId,
    required String text,
    required List<_Candidate> candidates,
  }) async {
    batonUpdateCalls.add((batonId: batonId, text: text, candidates: candidates));
  }

  @override
  Future<void> batonCancel({required String batonId}) async {
    batonCancelCalls.add(batonId);
  }

  @override
  Future<void> batonCreate({
    required String text,
    required List<_Candidate> candidates,
    String? replyToMessageId,
  }) async {
    batonCreateCalls.add((
      text: text,
      replyToMessageId: replyToMessageId,
      candidates: candidates,
    ));
  }
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

const _viewer = Profile(id: 'me', displayName: 'Me Myself');
const _other = Profile(id: 'other', displayName: 'Alex Other');

const _actionLabel = "Who'll take it?";

BeaconParticipant _participant(
  String userId,
  String name, {
  int roomAccess = RoomAccessBits.admitted,
}) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: 'b1',
  userId: userId,
  role: BeaconParticipantRoleBits.helper,
  status: 0,
  roomAccess: roomAccess,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  userTitle: name,
);

RoomMessage _message({
  String id = 'm1',
  Profile author = _viewer,
  int? semanticMarker,
  RoomBatonData? baton,
}) => RoomMessage(
  id: id,
  beaconId: 'b1',
  authorId: author.id,
  author: author,
  body: 'Who can drive on Friday?',
  createdAt: DateTime.utc(2026, 10, 3, 12),
  semanticMarker: semanticMarker,
  baton: baton,
);

const _taken = RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.taken,
  candidates: [],
  allAnswered: false,
  eligibleCount: 0,
  taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  selectionMode: RoomBatonSelectionMode.manual,
);

/// Fifteen admitted members besides the viewer: `Member 01` … `Member 15`.
List<BeaconParticipant> _crowd() => [
  for (var i = 1; i <= 15; i++)
    _participant(
      'u$i',
      'Member ${i.toString().padLeft(2, '0')}',
    ),
];

String _member(int i) => 'Member ${i.toString().padLeft(2, '0')}';

void main() {
  final getIt = GetIt.I;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<_MockRoomCubit> pumpRoom(
    WidgetTester tester, {
    List<RoomMessage>? messages,
    List<BeaconParticipant>? participants,
    bool batonEnabled = true,
    bool enableComposer = false,
    BeaconStatus status = BeaconStatus.open,
  }) async {
    final profileCubit = _MockProfileCubit(_viewer);
    final roomCubit = _MockRoomCubit(
      RoomState(
        beaconId: 'b1',
        myUserId: _viewer.id,
        beaconStatus: status,
        participants:
            participants ??
            [
              _participant(_viewer.id, _viewer.displayName),
              _participant('u-boris', 'Boris Driver'),
              _participant('u-clara', 'Clara Helper'),
              _participant(
                'u-dmitri',
                'Dmitri Pending',
                roomAccess: RoomAccessBits.requested,
              ),
            ],
        participantsLoaded: true,
        messages: messages ?? [_message()],
      ),
    );

    getIt
      ..registerSingleton<ProfileCubit>(profileCubit)
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );

    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<RoomCubit>.value(value: roomCubit),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(900, 1800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconRoomBody(
                  enableComposer: enableComposer,
                  batonEnabled: batonEnabled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return roomCubit;
  }

  Future<void> openActionsByLongPress(WidgetTester tester) async {
    expect(find.byType(RoomMessageTile), findsOneWidget);
    await tester.longPressAt(
      tester.getTopLeft(find.byType(RoomMessageTextBody)) + const Offset(8, 8),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openActionsBySecondaryTap(WidgetTester tester) async {
    expect(find.byType(RoomMessageTile), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.byType(RoomMessageTextBody)) + const Offset(8, 8),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreateSheet(WidgetTester tester) async {
    await openActionsByLongPress(tester);
    await tester.tap(find.text(_actionLabel));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.text(name));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  VoidCallback? askOnPressed(WidgetTester tester) {
    final button =
        find
                .ancestor(
                  of: find.text('Ask'),
                  matching: find.bySubtype<ButtonStyleButton>(),
                )
                .evaluate()
                .first
                .widget
            as ButtonStyleButton;
    return button.onPressed;
  }

  group('«Who\'ll take it?» message action', () {
    testWidgets('is offered on the viewer\'s own plain message', (
      tester,
    ) async {
      await pumpRoom(tester);
      await openActionsByLongPress(tester);

      expect(find.text(_actionLabel), findsOneWidget);
    });

    testWidgets('is also reachable through a secondary tap', (tester) async {
      await pumpRoom(tester);
      await openActionsBySecondaryTap(tester);

      expect(find.text(_actionLabel), findsOneWidget);
    });

    testWidgets('is also offered on someone else\'s message', (tester) async {
      await pumpRoom(tester, messages: [_message(author: _other)]);
      await openActionsByLongPress(tester);

      expect(find.text(_actionLabel), findsOneWidget);
    });

    testWidgets('is not offered while the feature flag is off', (tester) async {
      await pumpRoom(tester, batonEnabled: false);
      await openActionsByLongPress(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(_actionLabel), findsNothing);
    });

    testWidgets('is offered by the released default feature flag', (
      tester,
    ) async {
      // The released default enables the action without a test override.
      // The explicit disabled override is checked separately above.
      final profileCubit = _MockProfileCubit(_viewer);
      final roomCubit = _MockRoomCubit(
        RoomState(
          beaconId: 'b1',
          myUserId: _viewer.id,
          beaconStatus: BeaconStatus.open,
          messages: [_message()],
        ),
      );
      getIt
        ..registerSingleton<ProfileCubit>(profileCubit)
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<RoomCubit>.value(value: roomCubit),
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const TenturaResponsiveScope(
              child: Scaffold(body: BeaconRoomBody(enableComposer: false)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openActionsByLongPress(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(_actionLabel), findsOneWidget);
    });

    testWidgets('is not offered on a semantic (system) message', (
      tester,
    ) async {
      await pumpRoom(
        tester,
        messages: [
          _message(semanticMarker: BeaconRoomSemanticMarker.participantJoined),
        ],
      );
      await tester.longPressAt(
        tester.getTopLeft(find.byType(RoomMessageTextBody)) +
            const Offset(8, 8),
      );
      await tester.pumpAndSettle();

      expect(find.text(_actionLabel), findsNothing);
    });


    testWidgets('is not offered when the room is read-only', (tester) async {
      await pumpRoom(tester, status: BeaconStatus.closed);
      await openActionsByLongPress(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(_actionLabel), findsNothing);
    });
  });

  group('baton create sheet', () {
    testWidgets('lists admitted members and leaves out the viewer', (
      tester,
    ) async {
      await pumpRoom(tester);
      await openCreateSheet(tester);

      expect(find.text('Boris Driver'), findsOneWidget);
      expect(find.text('Clara Helper'), findsOneWidget);
      expect(
        find.widgetWithText(CheckboxListTile, 'Me Myself'),
        findsNothing,
      );
      // Not admitted to the room yet, so cannot be asked.
      expect(find.text('Dmitri Pending'), findsNothing);
    });

    testWidgets('keeps «Ask» disabled until someone is picked', (tester) async {
      await pumpRoom(tester);
      await openCreateSheet(tester);

      expect(askOnPressed(tester), isNull);

      await pick(tester, 'Boris Driver');
      expect(askOnPressed(tester), isNotNull);

      await pick(tester, 'Boris Driver');
      expect(askOnPressed(tester), isNull);
    });

    testWidgets('enables «Ask» at 12 picked and disables it at 13', (
      tester,
    ) async {
      await pumpRoom(
        tester,
        participants: [
          _participant(_viewer.id, _viewer.displayName),
          ..._crowd(),
        ],
      );
      await openCreateSheet(tester);

      for (var i = 1; i <= 12; i++) {
        await pick(tester, _member(i));
      }
      expect(askOnPressed(tester), isNotNull);

      await pick(tester, _member(13));
      expect(askOnPressed(tester), isNull);

      await pick(tester, _member(13));
      expect(askOnPressed(tester), isNotNull);
    });

    testWidgets('sends nothing when «Ask» is pressed with 13 picked', (
      tester,
    ) async {
      final cubit = await pumpRoom(
        tester,
        participants: [
          _participant(_viewer.id, _viewer.displayName),
          ..._crowd(),
        ],
      );
      await openCreateSheet(tester);

      for (var i = 1; i <= 13; i++) {
        await pick(tester, _member(i));
      }
      expect(askOnPressed(tester), isNull);

      await tester.ensureVisible(find.text('Ask'));
      await tester.tap(find.text('Ask'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cubit.batonCreateCalls, isEmpty);
    });

    testWidgets('submits all 12 people when «Ask» is pressed at the limit', (
      tester,
    ) async {
      final cubit = await pumpRoom(
        tester,
        participants: [
          _participant(_viewer.id, _viewer.displayName),
          ..._crowd(),
        ],
      );
      await openCreateSheet(tester);

      for (var i = 1; i <= 12; i++) {
        await pick(tester, _member(i));
      }
      await tester.ensureVisible(find.text('Ask'));
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(cubit.batonCreateCalls, hasLength(1));
      expect(
        cubit.batonCreateCalls.single.candidates.map((c) => c.userId),
        unorderedEquals([for (var i = 1; i <= 12; i++) 'u$i']),
      );
    });

    testWidgets('hides priority controls until «Set priority» is on', (
      tester,
    ) async {
      await pumpRoom(tester);
      await openCreateSheet(tester);
      await pick(tester, 'Boris Driver');
      await pick(tester, 'Clara Helper');

      expect(find.byType(SegmentedButton<int>), findsNothing);

      await tester.tap(find.text('Set priority'));
      await tester.pumpAndSettle();

      // One 1/2/3 control per selected person, none for the unpicked.
      expect(find.byType(SegmentedButton<int>), findsNWidgets(2));
    });

    testWidgets('submits every picked person at priority 1 by default', (
      tester,
    ) async {
      final cubit = await pumpRoom(tester);
      await openCreateSheet(tester);
      await pick(tester, 'Boris Driver');
      await pick(tester, 'Clara Helper');

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(cubit.batonCreateCalls, hasLength(1));
      // Posted as a new message replying to the one it started from.
      expect(cubit.batonCreateCalls.single.replyToMessageId, 'm1');
      expect(cubit.batonCreateCalls.single.text, isEmpty);
      expect(
        cubit.batonCreateCalls.single.candidates,
        unorderedEquals([
          (userId: 'u-boris', tier: 1),
          (userId: 'u-clara', tier: 1),
        ]),
      );
      // The sheet closes after asking.
      expect(find.text('Ask'), findsNothing);
    });

    testWidgets('submits the priority chosen for each person', (tester) async {
      final cubit = await pumpRoom(tester);
      await openCreateSheet(tester);
      await pick(tester, 'Boris Driver');
      await pick(tester, 'Clara Helper');
      await tester.tap(find.text('Set priority'));
      await tester.pumpAndSettle();

      final controls = find.byType(SegmentedButton<int>);
      // Controls follow the order of the list: Boris first, Clara second.
      await tester.tap(
        find.descendant(of: controls.at(1), matching: find.text('3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: controls.at(0), matching: find.text('2')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(
        cubit.batonCreateCalls.single.candidates,
        unorderedEquals([
          (userId: 'u-boris', tier: 2),
          (userId: 'u-clara', tier: 3),
        ]),
      );
    });

    testWidgets('shows the replied-to message and sends the typed ask', (
      tester,
    ) async {
      final cubit = await pumpRoom(tester);
      await openCreateSheet(tester);

      // The quote of the source message is in the sheet.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Who can drive on Friday?'),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '  Friday, 9:00  ');
      await pick(tester, 'Boris Driver');
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      expect(cubit.batonCreateCalls.single.text, 'Friday, 9:00');
      expect(cubit.batonCreateCalls.single.replyToMessageId, 'm1');
    });

    testWidgets('shows an avatar next to each member', (tester) async {
      await pumpRoom(tester);
      await openCreateSheet(tester);

      expect(
        find.descendant(
          of: find.widgetWithText(CheckboxListTile, 'Boris Driver'),
          matching: find.byType(TenturaAvatar),
        ),
        findsOneWidget,
      );
    });

    // Regression: the 1/2/3 control used to sit inside the CheckboxListTile,
    // whose MergeSemantics folded it into the row's node. The web engine only
    // gets the merged node, so with semantics on (web non-prod) a click on a
    // priority segment became the row's tap and unpicked the person instead.
    // The segment must be its own (not merged-up) tappable node.
    testWidgets('a semantics tap on a priority segment sets the priority', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final cubit = await pumpRoom(tester);
      await openCreateSheet(tester);
      await pick(tester, 'Boris Driver');
      await tester.tap(find.text('Set priority'));
      await tester.pumpAndSettle();

      tester.semantics.tap(
        // A node the engine actually receives: not merged up, with the
        // segment's label and tap after merging its own children.
        find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return !node.isMergedIntoParent &&
              data.label == '2' &&
              data.hasAction(SemanticsAction.tap);
        }),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      expect(
        cubit.batonCreateCalls.single.candidates,
        [(userId: 'u-boris', tier: 2)],
      );
      semantics.dispose();
    });
  });

  group('attach menu', () {
    Future<void> openAttachMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();
    }

    testWidgets('offers «Poll» and «Who\'ll take it?»', (tester) async {
      await pumpRoom(tester, enableComposer: true);
      await openAttachMenu(tester);

      expect(find.text('Poll'), findsOneWidget);
      expect(find.text(_actionLabel), findsOneWidget);
    });

    testWidgets('hides «Who\'ll take it?» while the feature flag is off', (
      tester,
    ) async {
      await pumpRoom(tester, enableComposer: true, batonEnabled: false);
      await openAttachMenu(tester);

      expect(find.text('Poll'), findsOneWidget);
      expect(find.text(_actionLabel), findsNothing);
    });

    testWidgets('starts a standalone baton: the ask is required and nothing '
        'is replied to', (tester) async {
      final cubit = await pumpRoom(tester, enableComposer: true);
      await openAttachMenu(tester);
      await tester.tap(find.text(_actionLabel));
      await tester.pumpAndSettle();

      await pick(tester, 'Boris Driver');
      expect(askOnPressed(tester), isNull, reason: 'no ask typed yet');

      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'Who can drive on Friday?',
      );
      await tester.pump();
      expect(askOnPressed(tester), isNotNull);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      final call = cubit.batonCreateCalls.single;
      expect(call.text, 'Who can drive on Friday?');
      expect(call.replyToMessageId, isNull);
      expect(call.candidates, [(userId: 'u-boris', tier: 1)]);
    });
  });

  group('baton message actions', () {
    const asking = RoomBatonAuthorData(
      id: 'baton-1',
      status: RoomBatonStatus.collecting,
      candidates: [
        RoomBatonCandidate(
          userId: 'u-boris',
          title: 'Boris Driver',
          tier: 2,
          response: RoomBatonResponse.canHelp,
        ),
      ],
      allAnswered: true,
      eligibleCount: 1,
    );

    RoomMessage batonMessage(RoomBatonData baton, {Profile author = _viewer}) =>
        _message(
          author: author,
          semanticMarker: BeaconRoomSemanticMarker.baton,
          baton: baton,
        );

    Future<void> longPressBaton(WidgetTester tester) async {
      await tester.longPressAt(
        tester.getTopLeft(find.byType(RoomBatonCard)) + const Offset(8, 8),
      );
      await tester.pumpAndSettle();
    }

    Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );

    void expectNoGenericActions() {
      for (final text in [
        '❤️',
        'Edit message',
        'Copy text',
        'Pin as fact',
        'Turn into…',
        _actionLabel,
      ]) {
        expect(inSheet(text), findsNothing, reason: text);
      }
    }

    testWidgets('the author of a collecting baton gets edit, reply, cancel '
        'and delete only', (tester) async {
      await pumpRoom(tester, messages: [batonMessage(asking)]);
      await longPressBaton(tester);

      for (final text in ['Edit', 'Reply', 'Cancel', 'Delete message']) {
        expect(inSheet(text), findsOneWidget, reason: text);
      }
      expectNoGenericActions();
    });

    testWidgets('once taken the author can only reply or delete', (
      tester,
    ) async {
      await pumpRoom(tester, messages: [batonMessage(_taken)]);
      await longPressBaton(tester);

      expect(inSheet('Reply'), findsOneWidget);
      expect(inSheet('Delete message'), findsOneWidget);
      expect(inSheet('Edit'), findsNothing);
      expect(inSheet('Cancel'), findsNothing);
      expectNoGenericActions();
    });

    testWidgets('everyone else can only reply', (tester) async {
      await pumpRoom(
        tester,
        messages: [
          batonMessage(
            const RoomBatonObserverData(
              id: 'baton-1',
              status: RoomBatonStatus.collecting,
            ),
            author: _other,
          ),
        ],
      );
      await longPressBaton(tester);

      expect(inSheet('Reply'), findsOneWidget);
      for (final text in ['Edit', 'Cancel', 'Delete message']) {
        expect(inSheet(text), findsNothing, reason: text);
      }
      expectNoGenericActions();
    });

    testWidgets('a plain tap on the baton bubble opens the baton menu', (
      tester,
    ) async {
      await pumpRoom(tester, messages: [batonMessage(asking)]);
      await tester.tapAt(
        tester.getTopLeft(find.byType(RoomBatonCard)) + const Offset(8, 8),
      );
      await tester.pumpAndSettle();

      expect(inSheet('Edit'), findsOneWidget);
      expect(inSheet('Cancel'), findsOneWidget);
      expectNoGenericActions();
    });

    testWidgets('a tap on a card button does its own job, not the menu', (
      tester,
    ) async {
      await pumpRoom(tester, messages: [batonMessage(asking)]);
      await tester.tap(find.text('Choose now'));
      await tester.pumpAndSettle();

      // The choose sheet, not the message menu.
      expect(find.text('Pick for me'), findsOneWidget);
      expect(inSheet('Edit'), findsNothing);
    });

    testWidgets('«Edit» opens the sheet filled in and saves the change', (
      tester,
    ) async {
      final cubit = await pumpRoom(tester, messages: [batonMessage(asking)]);
      await longPressBaton(tester);
      await tester.tap(inSheet('Edit'));
      await tester.pumpAndSettle();

      final field = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Who can drive on Friday?',
      );
      // Boris is already asked, at priority 2 (so priorities are shown).
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Boris Driver'),
            )
            .value,
        isTrue,
      );
      expect(find.byType(SegmentedButton<int>), findsOneWidget);

      await tester.enterText(field, 'Who can drive on Saturday?');
      await pick(tester, 'Clara Helper');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final call = cubit.batonUpdateCalls.single;
      expect(call.batonId, 'baton-1');
      expect(call.text, 'Who can drive on Saturday?');
      expect(
        call.candidates,
        unorderedEquals([
          (userId: 'u-boris', tier: 2),
          (userId: 'u-clara', tier: 1),
        ]),
      );
    });

    testWidgets('«Cancel» asks for confirmation, then cancels', (tester) async {
      final cubit = await pumpRoom(tester, messages: [batonMessage(asking)]);
      await longPressBaton(tester);
      await tester.tap(inSheet('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(cubit.batonCancelCalls, isEmpty);
      // Both buttons name what they do; no ambiguous bare «Cancel».
      Finder inDialog(String text) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(text),
      );
      expect(inDialog('Keep it'), findsOneWidget);
      expect(inDialog('Cancel the ask'), findsOneWidget);
      expect(inDialog('Cancel'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(cubit.batonCancelCalls, ['baton-1']);
    });
  });
}
