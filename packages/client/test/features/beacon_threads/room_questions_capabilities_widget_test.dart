// The Questions preset of `RoomCapabilities` turns the Request chat into a
// plain reply thread: the composer offers no attach, fact, poll or baton, and
// the message actions keep Reply / Copy / Edit / Delete but none of the
// features limited to admitted people (pin fact, new Request, plan, baton).
// Request rooms keep all of them.

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
const _questionsId = 'questions-1';

final _createdAt = DateTime.utc(2026, 6, 30, 12);

RoomMessage _message({required Profile author, String id = 'm1'}) =>
    RoomMessage(
      id: id,
      beaconId: 'b1',
      authorId: author.id,
      author: author,
      body: 'Is the gate open on Sunday?',
      createdAt: _createdAt,
    );

/// A writable thread room (the viewer may post, as the server's `canPost`
/// says for a Questions audience member) with [messages].
RoomState _threadState(List<RoomMessage> messages) =>
    roomBodyState(threadItemId: _questionsId, messages: messages).copyWith(
      lobbyCanPost: true,
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: 'b1',
          profile: _viewer,
        ),
      ],
      participantsLoaded: true,
    );

RoomState _generalState(List<RoomMessage> messages) =>
    roomBodyState(messages: messages).copyWith(
      participants: [
        roomBodyAdmittedParticipant(
          beaconId: 'b1',
          profile: _viewer,
          role: BeaconParticipantRoleBits.author,
        ),
      ],
      participantsLoaded: true,
    );

Future<void> _pumpRoomBody(
  WidgetTester tester, {
  required RoomState roomState,
  required RoomCapabilities capabilities,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);

  final profileCubit = RoomBodyHarnessProfileCubit(_viewer);
  final roomCubit = RoomBodyHarnessCubit(roomState);

  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

  await tester.binding.setSurfaceSize(const Size(700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: roomCubit),
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
              body: BeaconRoomBody(capabilities: capabilities),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openActionsSheet(WidgetTester tester) async {
  final inline = find.byType(RoomMessageTextBody);
  final body = inline.evaluate().isNotEmpty
      ? inline
      : find.byType(ShowMoreText);
  await tester.longPressAt(tester.getTopLeft(body.first) + const Offset(8, 8));
  // Bounded: the surface hosts an animation that never settles.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(BottomSheet), findsOneWidget);
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  final l10n = lookupL10n(const Locale('en'));

  group('RoomCapabilities.questions preset', () {
    test('turns every admitted-only feature off', () {
      const caps = RoomCapabilities.questions();
      expect(caps.facts, isFalse);
      expect(caps.blocker, isFalse);
      expect(caps.plan, isFalse);
      expect(caps.coordinationItems, isFalse);
      expect(caps.childPromotion, isFalse);
      expect(caps.commitmentSheet, isFalse);
      expect(caps.closure, isFalse);
    });
  });

  group('composer follows room capabilities', () {
    testWidgets('Questions composer is a plain text box without attach, fact, '
        'poll or baton', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: _threadState([_message(author: _other)]),
        capabilities: const RoomCapabilities.questions(),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const ValueKey('attach')), findsNothing);
      expect(find.byKey(const ValueKey('paste')), findsNothing);
      expect(find.text(l10n.beaconRoomAttachPickFact), findsNothing);
      expect(find.text(l10n.beaconRoomAttachCreatePoll), findsNothing);
      expect(find.text(l10n.beaconRoomAttachCreateBaton), findsNothing);
    });

    testWidgets('Request composer offers attach with fact, poll and baton', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _generalState([_message(author: _other)]),
        capabilities: const RoomCapabilities.request(),
      );

      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(l10n.beaconRoomAttachPickFact), findsOneWidget);
      expect(find.text(l10n.beaconRoomAttachCreatePoll), findsOneWidget);
      expect(find.text(l10n.beaconRoomAttachCreateBaton), findsOneWidget);
    });
  });

  group('message actions follow room capabilities', () {
    testWidgets('Questions own message offers Reply, Copy, Edit and Delete', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _threadState([_message(author: _viewer)]),
        capabilities: const RoomCapabilities.questions(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionCopyText), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionEditMessage), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionDeleteMessage), findsOneWidget);
    });

    testWidgets('Questions own message offers no admitted-only action', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _threadState([_message(author: _viewer)]),
        capabilities: const RoomCapabilities.questions(),
      );
      await _openActionsSheet(tester);

      // Thread mode already hides most of these on its own; Start baton is
      // the one only the room capabilities keep out. The matching guard for
      // the rest is the General-room test below.
      // The sheet is the real one: it still carries Reply.
      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconCreateChildRequest), findsNothing);
      expect(find.text(l10n.postBudAction), findsNothing);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsNothing);
      expect(find.text(l10n.beaconRoomActionPinFact), findsNothing);
      expect(
        find.text(l10n.beaconRoomActionUpdatePlanFromMessage),
        findsNothing,
      );
      expect(find.text(l10n.batonActionStart), findsNothing);
    });

    testWidgets("Questions another member's message offers Reply and Copy "
        'but not Edit or Delete', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: _threadState([_message(author: _other)]),
        capabilities: const RoomCapabilities.questions(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionCopyText), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionEditMessage), findsNothing);
      expect(find.text(l10n.beaconRoomActionDeleteMessage), findsNothing);
    });

    testWidgets('Questions capabilities in a writable room hide Pin fact, '
        'Turn into and Create child request', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: _generalState([_message(author: _viewer)]),
        capabilities: const RoomCapabilities.questions(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionPinFact), findsNothing);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsNothing);
      expect(find.text(l10n.beaconCreateChildRequest), findsNothing);
    });

    testWidgets('Request room still offers Start baton on an own message', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _generalState([_message(author: _viewer)]),
        capabilities: const RoomCapabilities.request(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.batonActionStart), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionPinFact), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsOneWidget);
      expect(find.text(l10n.beaconCreateChildRequest), findsOneWidget);
    });
  });
}
