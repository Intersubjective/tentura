// #479 client UI:
//  - the marker-12 «{name} took it.» system line no longer repeats the baton
//    card right above it; further down the room it says what was taken;
//  - «Create a plan step with {name}?» is prefilled from the ask and
//    editable; «Not now» creates nothing; a failed save keeps the sheet open
//    for another try, and a successful one closes it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/entity/baton_select_result.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_plan_step_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'room_cubit_fakes.dart';

const _viewer = Profile(id: 'u-viewer', displayName: 'Viewer');
const _anna = Profile(id: 'u-anna', displayName: 'Anna Author');

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

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(child: Scaffold(body: child)),
  ),
);

final _participants = [
  BeaconParticipant(
    id: 'p-boris',
    beaconId: 'b-baton',
    userId: 'u-boris',
    role: 2,
    status: 0,
    roomAccess: 3,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    userTitle: 'Boris Driver',
  ),
];

final _source = RoomMessage(
  id: 'msg-1',
  beaconId: 'b-baton',
  authorId: _anna.id,
  author: _anna,
  body: 'Can you also bring straps?',
  createdAt: DateTime.utc(2026, 10, 3, 12),
);

final _other = RoomMessage(
  id: 'msg-2',
  beaconId: 'b-baton',
  authorId: _anna.id,
  author: _anna,
  body: 'See you at nine',
  createdAt: DateTime.utc(2026, 10, 3, 12, 30),
);

final _tookIt = RoomMessage(
  id: 'sys-1',
  beaconId: 'b-baton',
  authorId: _anna.id,
  author: _anna,
  body: '',
  createdAt: DateTime.utc(2026, 10, 3, 13),
  semanticMarker: BeaconRoomSemanticMarker.batonTaken,
  systemPayloadJson:
      '{"batonId":"baton-1","sourceMessageId":"msg-1",'
      '"takerUserId":"u-boris"}',
);

Widget _tile(RoomMessage? previous, {RoomCubit? room}) => MultiBlocProvider(
  providers: [
    if (room != null) BlocProvider<RoomCubit>.value(value: room),
    BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
    BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
    BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
  ],
  child: _app(
    RoomMessageTile(
      message: _tookIt,
      previousMessage: previous,
      myProfile: _viewer,
      participants: _participants,
    ),
  ),
);

const _offer = BatonPlanStepOffer(
  beaconId: 'b-baton',
  batonId: 'baton-1',
  stepId: 'PS0000000000aa',
  assigneeId: 'u-boris',
  assigneeName: 'Boris Driver',
  title: 'Can you also bring straps?',
);

void main() {
  group('«{name} took it.» system line', () {
    testWidgets('is not shown right under its baton card', (tester) async {
      await tester.pumpWidget(_tile(_source));
      await tester.pump();

      expect(find.textContaining('took it'), findsNothing);
    });

    testWidgets('further down, it is shown once', (tester) async {
      await tester.pumpWidget(_tile(_other));
      await tester.pump();

      expect(find.text('Boris Driver took it.'), findsOneWidget);
    });

    testWidgets('further down, it says what was taken when the ask is loaded', (
      tester,
    ) async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final repo = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
        ..messages = [_source, _other, _tookIt];
      final room = roomCubitForTest(repo);
      await tester.runAsync(() => awaitRoomCubitLoad(room));
      addTearDown(() => tester.runAsync(room.close));

      await tester.pumpWidget(_tile(_other, room: room));
      await tester.pump();

      expect(
        find.text('Boris Driver took it: Can you also bring straps?'),
        findsOneWidget,
      );
    });
  });

  group('RoomBatonPlanStepSheet', () {
    Future<List<String>> open(
      WidgetTester tester, {
      required List<bool> answers,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => RoomBatonPlanStepSheet.show(
                context,
                offer: _offer,
                onCreate: (title) async {
                  calls.add(title);
                  return answers.removeAt(0);
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('asks about the taker, prefilled from the ask', (tester) async {
      await open(tester, answers: []);

      expect(
        find.text('Create a plan step with Boris Driver?'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Can you also bring straps?',
      );
    });

    testWidgets('«Not now» creates nothing', (tester) async {
      final calls = await open(tester, answers: []);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.byType(RoomBatonPlanStepSheet), findsNothing);
    });

    testWidgets('a failed save keeps the sheet for another try', (
      tester,
    ) async {
      final calls = await open(tester, answers: [false, true]);
      await tester.enterText(find.byType(TextField), 'Bring 4 straps');
      await tester.pump();

      await tester.tap(find.text('Create step'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomBatonPlanStepSheet), findsOneWidget);

      await tester.tap(find.text('Create step'));
      await tester.pumpAndSettle();

      expect(calls, ['Bring 4 straps', 'Bring 4 straps']);
      expect(find.byType(RoomBatonPlanStepSheet), findsNothing);
    });

    testWidgets('an empty title cannot be saved', (tester) async {
      final calls = await open(tester, answers: [true]);
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();

      await tester.tap(find.text('Create step'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });
  });
}
