// «Оформить запрос» in a Post room (plan D1): the message actions offer it on
// the viewer's own plain messages only, reachable by secondary tap (never
// long-press alone), and nothing shows while `kPostBuddingEnabled` is off.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _other = Profile(id: 'other', displayName: 'Alex');

final _createdAt = DateTime.utc(2026, 10, 1, 12);

RoomMessage _message(Profile author, {int? semanticMarker}) => RoomMessage(
  id: 'm-${author.id}',
  beaconId: 'p1',
  authorId: author.id,
  author: author,
  body: 'We need a ladder on Saturday',
  createdAt: _createdAt,
  semanticMarker: semanticMarker,
);

Future<void> _pump(
  WidgetTester tester, {
  required RoomMessage message,
  required bool enabled,
  RoomCapabilities capabilities = const RoomCapabilities.post(),
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = RoomBodyHarnessProfileCubit(_viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final state = roomBodyState(beaconId: 'p1', messages: [message]).copyWith(
    participants: [
      roomBodyAdmittedParticipant(
        beaconId: 'p1',
        profile: _viewer,
        role: BeaconParticipantRoleBits.addressee,
      ),
    ],
    participantsLoaded: true,
  );

  await tester.binding.setSurfaceSize(const Size(700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: RoomBodyHarnessCubit(state)),
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconRoomBody(
                enableComposer: false,
                capabilities: capabilities,
                postBuddingEnabled: enabled,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Opens the message actions with a secondary (right) click.
Future<void> _secondaryTapMessage(WidgetTester tester) async {
  final inline = find.byType(RoomMessageTextBody);
  final body = inline.evaluate().isNotEmpty
      ? inline
      : find.byType(ShowMoreText);
  await tester.tapAt(
    tester.getTopLeft(body.first) + const Offset(8, 8),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(BottomSheet), findsOneWidget);
}

final _budAction = find.byKey(const Key('Room.BudRequestAction'));

void main() {
  testWidgets('own message offers «Make a request» via secondary tap', (
    tester,
  ) async {
    await _pump(tester, message: _message(_viewer), enabled: true);
    await _secondaryTapMessage(tester);
    expect(_budAction, findsOneWidget);
    expect(find.text('Make a request'), findsOneWidget);
  });

  testWidgets("another member's message never offers it", (tester) async {
    await _pump(tester, message: _message(_other), enabled: true);
    await _secondaryTapMessage(tester);
    expect(_budAction, findsNothing);
  });

  testWidgets('a semantic-marker message is not a bud source', (tester) async {
    await _pump(
      tester,
      message: _message(
        _viewer,
        semanticMarker: BeaconRoomSemanticMarker.done,
      ),
      enabled: true,
    );
    await _secondaryTapMessage(tester);
    expect(_budAction, findsNothing);
  });

  testWidgets('gate off hides the action', (tester) async {
    await _pump(tester, message: _message(_viewer), enabled: false);
    await _secondaryTapMessage(tester);
    expect(_budAction, findsNothing);
  });

  testWidgets('a Request room never offers it', (tester) async {
    await _pump(
      tester,
      message: _message(_viewer),
      enabled: true,
      capabilities: const RoomCapabilities.request(),
    );
    await _secondaryTapMessage(tester);
    expect(_budAction, findsNothing);
  });
}
