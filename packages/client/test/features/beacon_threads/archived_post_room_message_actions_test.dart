// Message actions in an archived (closed) Post room. Deleting one's own
// message and budding a Request from it stay available (personal actions and
// plan D1); reply, reactions and edit do not. A baton message offers its
// author delete only; nobody else gets a menu for it.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/reaction_quick_picker.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _other = Profile(id: 'other', displayName: 'Alex');

final _createdAt = DateTime.utc(2026, 10, 27, 12);

RoomMessage _message(Profile author) => RoomMessage(
  id: 'm-${author.id}',
  beaconId: 'p1',
  authorId: author.id,
  author: author,
  body: 'We need a ladder on Saturday',
  createdAt: _createdAt,
);

RoomMessage _batonMessage(Profile author, RoomBatonData baton) => RoomMessage(
  id: 'baton-msg-${author.id}',
  beaconId: 'p1',
  authorId: author.id,
  author: author,
  body: 'Who can drive on Friday?',
  createdAt: _createdAt,
  semanticMarker: BeaconRoomSemanticMarker.baton,
  baton: baton,
);

const _collecting = RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  candidates: [
    RoomBatonCandidate(
      userId: 'other',
      title: 'Alex',
      tier: 1,
      response: RoomBatonResponse.canHelp,
    ),
  ],
  allAnswered: true,
  eligibleCount: 1,
);

Future<void> _pumpArchivedRoom(
  WidgetTester tester, {
  required RoomMessage message,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = RoomBodyHarnessProfileCubit(_viewer);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final state =
      roomBodyState(
        beaconId: 'p1',
        messages: [message],
        beaconStatus: BeaconStatus.closed,
      ).copyWith(
        participants: [
          roomBodyAdmittedParticipant(
            beaconId: 'p1',
            profile: _viewer,
            role: BeaconParticipantRoleBits.addressee,
          ),
          roomBodyAdmittedParticipant(
            beaconId: 'p1',
            profile: _other,
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
        home: const MediaQuery(
          data: MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            // Budding and batons are on by default (kPostBuddingEnabled,
            // kBatonEnabled).
            child: Scaffold(
              body: BeaconRoomBody(
                enableComposer: false,
                capabilities: RoomCapabilities.post(),
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

/// Opens the actions of the plain message with a secondary (right) click.
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
}

Future<void> _longPressBaton(WidgetTester tester) async {
  await tester.longPressAt(
    tester.getTopLeft(find.byType(RoomBatonCard)) + const Offset(8, 8),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _inSheet(String text) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(text),
);

final _budAction = find.byKey(const Key('Room.BudRequestAction'));

void main() {
  group('archived Post room: ordinary message actions', () {
    testWidgets('own message offers delete and «Make a request», nothing to '
        'write', (tester) async {
      await _pumpArchivedRoom(tester, message: _message(_viewer));
      await _secondaryTapMessage(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(_inSheet('Delete message'), findsOneWidget);
      expect(_budAction, findsOneWidget);
      expect(_inSheet('Make a request'), findsOneWidget);

      expect(_inSheet('Reply'), findsNothing);
      expect(_inSheet('Edit message'), findsNothing);
      expect(find.byType(ReactionQuickPicker), findsNothing);
    });

    testWidgets("another member's message offers neither delete nor bud", (
      tester,
    ) async {
      await _pumpArchivedRoom(tester, message: _message(_other));
      await _secondaryTapMessage(tester);

      expect(_inSheet('Delete message'), findsNothing);
      expect(_budAction, findsNothing);
      expect(_inSheet('Reply'), findsNothing);
      expect(_inSheet('Edit message'), findsNothing);
      expect(find.byType(ReactionQuickPicker), findsNothing);
    });
  });

  group('archived Post room: baton message actions', () {
    testWidgets('own baton message offers delete only', (tester) async {
      await _pumpArchivedRoom(
        tester,
        message: _batonMessage(_viewer, _collecting),
      );
      await _longPressBaton(tester);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(_inSheet('Delete message'), findsOneWidget);
      for (final text in ['Edit', 'Reply', 'Cancel', 'Make a request']) {
        expect(_inSheet(text), findsNothing, reason: text);
      }
    });

    testWidgets("another member's baton message opens no menu", (
      tester,
    ) async {
      await _pumpArchivedRoom(
        tester,
        message: _batonMessage(
          _other,
          const RoomBatonObserverData(
            id: 'baton-2',
            status: RoomBatonStatus.collecting,
          ),
        ),
      );
      await _longPressBaton(tester);

      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
