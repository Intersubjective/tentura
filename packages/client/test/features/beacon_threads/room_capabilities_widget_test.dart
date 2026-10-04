// Room widgets honour the host's `RoomCapabilities`: a Post room (all
// Request-only features off) shows no Request actions in the message actions
// sheet, no pinned NOW row, no commitment sheet, child-promotion footer, fact
// history or closure story card; a Request room (`request()`) keeps them all.
// `BeaconRoomSurface` takes a `RoomHost` and rebuilds when `host.changes` fires.

import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_closure_story_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../beacon_create/fake_beacon_ports.dart';
import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _other = Profile(id: 'other', displayName: 'Alex');
const _nowLine = 'Bring the ladder to the north gate';

final _createdAt = DateTime.utc(2026, 6, 30, 12);

RoomMessage _plainMessage({String id = 'm-plain'}) => RoomMessage(
  id: id,
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body: 'Hello room',
  createdAt: _createdAt,
);

RoomMessage _planLinkedMessage() => RoomMessage(
  id: 'm-plan',
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body: 'Plan: ladder first',
  createdAt: _createdAt,
  linkedItemId: 'item-plan',
  linkedItemKind: CoordinationItemKind.plan.value,
  linkedItemStatus: CoordinationItemStatus.open.value,
  linkedItemCreatorId: _other.id,
  linkedItemCreatedAt: _createdAt,
  linkedItemUpdatedAt: _createdAt,
);

BeaconFactCard _fact({required String sourceMessageId}) => BeaconFactCard(
  id: 'fact-1',
  beaconId: 'b1',
  factText: 'Gate code is 4821',
  visibility: 0,
  pinnedBy: _other.id,
  createdAt: _createdAt,
  status: 0,
  sourceMessageId: sourceMessageId,
);

/// Pumps [BeaconRoomBody] under a seeded cubit with [capabilities] passed in.
Future<void> _pumpRoomBody(
  WidgetTester tester, {
  required RoomState roomState,
  required RoomCapabilities capabilities,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);

  final profileCubit = RoomBodyHarnessProfileCubit(_viewer);
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  final roomCubit = RoomBodyHarnessCubit(roomState);

  getIt.registerSingleton<ProfileCubit>(profileCubit);
  getIt.registerSingleton<ImageRepository>(ImageRepository());
  getIt.registerSingleton<ClipboardImageRepository>(
    ClipboardImageRepository(),
  );

  await tester.binding.setSurfaceSize(const Size(700, 900));
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
          data: const MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BeaconRoomBody(
                enableComposer: false,
                capabilities: capabilities,
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

/// Seeds the viewer as the Request author so plan editing is allowed.
RoomState _state({
  required List<RoomMessage> messages,
  List<BeaconFactCard> factCards = const [],
  BeaconRoomState? roomState,
}) {
  final base = roomBodyState(messages: messages);
  return base.copyWith(
    factCards: factCards,
    roomState: roomState,
    participants: [
      roomBodyAdmittedParticipant(
        beaconId: 'b1',
        profile: _viewer,
        role: BeaconParticipantRoleBits.author,
      ),
    ],
    participantsLoaded: true,
  );
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

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _StubRouter extends Mock implements StackRouter {}

Future<void> _pumpTile(
  WidgetTester tester, {
  required RoomMessage message,
  required RoomCapabilities capabilities,
  List<BeaconParticipant> participants = const [],
  String? promotedChildBeaconId,
}) async {
  await tester.pumpWidget(
    StackRouterScope(
      controller: _StubRouter(),
      stateHash: 0,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
          BlocProvider<PresenceCubit>.value(
            value: RoomBodyHarnessPresenceCubit(),
          ),
          BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
        ],
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 900)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RoomMessageTile(
                    message: message,
                    myProfile: _viewer,
                    participants: participants,
                    promotedChildBeaconId: promotedChildBeaconId,
                    capabilities: capabilities,
                    onToggleReaction: (_, _) async {},
                  ),
                ),
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

/// Fake [RoomHost] whose admission flag can flip and announce on [changes].
class _FakeRoomHost implements RoomHost {
  final _changes = StreamController<void>.broadcast();

  @override
  bool isAdmissionBlocked = false;

  @override
  bool coordinationDeniesAdmission = false;

  @override
  RoomCapabilities capabilities = const RoomCapabilities.post();

  @override
  String get beaconId => 'b1';

  @override
  Profile get author => _other;

  @override
  BeaconStatus get status => BeaconStatus.open;

  @override
  Stream<void> get changes => _changes.stream;

  void announce() => _changes.add(null);

  Future<void> close() => _changes.close();
}

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream.value(_state);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

BeaconParticipant _committedHelper() => BeaconParticipant(
  id: 'p-other',
  beaconId: 'b1',
  userId: _other.id,
  role: BeaconParticipantRoleBits.helper,
  status: BeaconParticipantStatusBits.offeredHelp,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _createdAt,
  updatedAt: _createdAt,
  userTitle: 'Alex',
  helpType: '["transport"]',
  roleLabel: 'Pickup lead',
);

RoomMessage _factEditedMessage() => RoomMessage(
  id: 'sys-fact-edited',
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body: '',
  createdAt: _createdAt,
  semanticMarker: BeaconRoomSemanticMarker.factEdited,
  systemPayloadJson: jsonEncode({
    'factCardId': 'fact-1',
    'pinnedBy': _viewer.id,
    'factText': 'Gate code is 4821',
    'revisionSeq': 2,
  }),
);

void _registerHierarchyWithChildPreview() {
  final port = FakeBeaconHierarchyRepositoryPort();
  port.childPreviews['child-1'] = BeaconHierarchySummary(
    beaconId: 'child-1',
    title: 'Fix the fence',
    owner: const BeaconHierarchyOwnerSummary(
      id: 'author-1',
      displayName: 'Alice',
    ),
    status: BeaconStatus.open,
    publishedAt: DateTime.utc(2026),
    isTombstone: false,
  );
  GetIt.I.registerSingleton<BeaconHierarchyCase>(
    buildBeaconHierarchyCaseForTest(
      port,
      createCase: BeaconCreateCase(
        FakeBeaconWritePort(),
        FakeBeaconImagePort(),
      ),
      beacons: FakeBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
  );
}

/// Room cubit the [ThreadHostCubit] hands to the surface: seeded state, no I/O.
class _SurfaceRoomCubit extends RoomBodyHarnessCubit {
  _SurfaceRoomCubit(super.initial);

  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;

  @override
  Future<void> load() async {}

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}
}

/// Pumps [BeaconRoomSurface] for [host] with a seeded General room and
/// resolves once the room body is on screen.
Future<void> _pumpSurface(
  WidgetTester tester, {
  required _FakeRoomHost host,
  required RoomState roomState,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = RoomBodyHarnessProfileCubit(_viewer);
  getIt.registerSingleton<ProfileCubit>(profileCubit);
  getIt.registerSingleton<ImageRepository>(ImageRepository());
  getIt.registerSingleton<ClipboardImageRepository>(
    ClipboardImageRepository(),
  );

  final threadHost = ThreadHostCubit(
    beaconId: 'b1',
    roomCubitFactory:
        ({
          required String beaconId,
          String? threadItemId,
          DateTime? initialUnreadAnchorAt,
          RoomCapabilities capabilities = const RoomCapabilities.request(),
        }) => _SurfaceRoomCubit(roomState),
  );
  // Unmount and flush first: disposing the surface schedules the room lease's
  // deferred drop on the fake clock. That drop chains onto `ThreadHostCubit`'s
  // internal `_switchTail`, a `Future` born inside this test's FakeAsync zone;
  // a bare `await` on it from here never resumes even once it has genuinely
  // settled (a known FakeAsync-zone quirk), so race it with a timeout instead
  // of awaiting it directly.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final closing = threadHost.close();
    await tester.pump();
    await closing;
  });
  final general = RequestThread(
    threadId: RequestThread.generalId,
    kind: RequestThreadKind.general,
    lastSeenAt: _createdAt,
  );

  await tester.binding.setSurfaceSize(const Size(700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    StackRouterScope(
      controller: _StubRouter(),
      stateHash: 0,
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(700, 900)),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ThreadsCubit>.value(
                  value: _MockThreadsCubit(
                    ThreadsState(
                      threads: [general],
                      myUserId: _viewer.id,
                      status: const StateIsSuccess(),
                    ),
                  ),
                ),
                BlocProvider<ThreadHostCubit>.value(value: threadHost),
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<PresenceCubit>.value(
                  value: RoomBodyHarnessPresenceCubit(),
                ),
              ],
              child: Scaffold(
                body: BeaconRoomSurface(
                  host: host,
                  roomLease: BeaconRoomLease(host: threadHost),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byType(BeaconRoomBody), findsOneWidget);
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  final l10n = lookupL10n(const Locale('en'));

  group('message actions sheet follows room capabilities', () {
    testWidgets('Post room offers no Request-only actions on a plain message', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _state(messages: [_plainMessage()]),
        capabilities: const RoomCapabilities.post(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsNothing);
      expect(find.text(l10n.beaconCreateChildRequest), findsNothing);
      expect(
        find.text(l10n.beaconRoomActionUpdatePlanFromMessage),
        findsNothing,
      );
      expect(find.text(l10n.beaconRoomActionPinFact), findsNothing);
    });

    testWidgets('Request room offers the Request-only actions on a plain '
        'message', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: _state(messages: [_plainMessage()]),
        capabilities: const RoomCapabilities.request(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionTurnInto), findsOneWidget);
      expect(find.text(l10n.beaconCreateChildRequest), findsOneWidget);
      expect(
        find.text(l10n.beaconRoomActionUpdatePlanFromMessage),
        findsOneWidget,
      );
      expect(find.text(l10n.beaconRoomActionPinFact), findsOneWidget);
    });

    testWidgets('Post room offers no Jump to plan on a plan-linked message', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _state(messages: [_planLinkedMessage()]),
        capabilities: const RoomCapabilities.post(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionJumpToPlan), findsNothing);
    });

    testWidgets('Request room offers Jump to plan on a plan-linked message', (
      tester,
    ) async {
      await _pumpRoomBody(
        tester,
        roomState: _state(messages: [_planLinkedMessage()]),
        capabilities: const RoomCapabilities.request(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionJumpToPlan), findsOneWidget);
    });

    testWidgets('Post room offers no View pinned fact on a fact-backed '
        'message', (tester) async {
      final message = _plainMessage();
      await _pumpRoomBody(
        tester,
        roomState: _state(
          messages: [message],
          factCards: [_fact(sourceMessageId: message.id)],
        ),
        capabilities: const RoomCapabilities.post(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionViewPinnedFact), findsNothing);
      expect(find.text(l10n.beaconRoomActionPinFact), findsNothing);
    });

    testWidgets('Request room offers View pinned fact on a fact-backed '
        'message', (tester) async {
      final message = _plainMessage();
      await _pumpRoomBody(
        tester,
        roomState: _state(
          messages: [message],
          factCards: [_fact(sourceMessageId: message.id)],
        ),
        capabilities: const RoomCapabilities.request(),
      );
      await _openActionsSheet(tester);

      expect(find.text(l10n.beaconRoomActionViewPinnedFact), findsOneWidget);
    });
  });

  group('pinned NOW row follows room capabilities', () {
    final nowState = _state(
      messages: [_plainMessage()],
      roomState: BeaconRoomState(
        beaconId: 'b1',
        updatedAt: _createdAt,
        currentLine: _nowLine,
      ),
    );

    testWidgets('Post room shows no pinned NOW row', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: nowState,
        capabilities: const RoomCapabilities.post(),
      );

      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsNothing,
      );
    });

    testWidgets('Request room shows the pinned NOW row', (tester) async {
      await _pumpRoomBody(
        tester,
        roomState: nowState,
        capabilities: const RoomCapabilities.request(),
      );

      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('message tile follows room capabilities', () {
    testWidgets('Post room does not render a closure story card', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        message: RoomMessage(
          id: 'story-1',
          beaconId: 'b1',
          authorId: _other.id,
          author: _other,
          body: 'We got it all done.',
          createdAt: _createdAt,
          systemMessageKind: BeaconRoomSystemMessageKind.closureStory,
        ),
        capabilities: const RoomCapabilities.post(),
      );

      expect(find.byType(RoomClosureStoryCard), findsNothing);
    });

    testWidgets('Request room renders a closure story card', (tester) async {
      await _pumpTile(
        tester,
        message: RoomMessage(
          id: 'story-1',
          beaconId: 'b1',
          authorId: _other.id,
          author: _other,
          body: 'We got it all done.',
          createdAt: _createdAt,
          systemMessageKind: BeaconRoomSystemMessageKind.closureStory,
        ),
        capabilities: const RoomCapabilities.request(),
      );

      expect(find.byType(RoomClosureStoryCard), findsOneWidget);
    });

    testWidgets('Post room does not render a child promotion footer', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        message: _plainMessage(),
        capabilities: const RoomCapabilities.post(),
        promotedChildBeaconId: 'child-1',
      );

      expect(find.byType(BeaconChildPromotionFooter), findsNothing);
    });

    testWidgets('Request room renders the child promotion footer', (
      tester,
    ) async {
      _registerHierarchyWithChildPreview();
      await _pumpTile(
        tester,
        message: _plainMessage(),
        capabilities: const RoomCapabilities.request(),
        promotedChildBeaconId: 'child-1',
      );

      expect(find.byType(BeaconChildPromotionFooter), findsOneWidget);
      expect(find.text('Fix the fence'), findsOneWidget);
    });

    testWidgets('Post room opens no commitment sheet from the role label', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        message: _plainMessage(),
        capabilities: const RoomCapabilities.post(),
        participants: [_committedHelper()],
      );

      final glyphs = find.byKey(
        TestIds.key(TestIds.roomAuthorCommitmentGlyphs),
      );
      if (glyphs.evaluate().isNotEmpty) {
        await tester.tap(glyphs, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Role'), findsNothing);
    });

    testWidgets('Request room opens the commitment sheet from the role label', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        message: _plainMessage(),
        capabilities: const RoomCapabilities.request(),
        participants: [_committedHelper()],
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.roomAuthorCommitmentGlyphs)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Pickup lead'), findsWidgets);
    });

    testWidgets('Post room offers no fact history link on a fact-edit line', (
      tester,
    ) async {
      await _pumpTile(
        tester,
        message: _factEditedMessage(),
        capabilities: const RoomCapabilities.post(),
      );

      expect(find.text(l10n.beaconRoomFactWhatChanged), findsNothing);
    });

    testWidgets('Request room offers the fact history link on a fact-edit '
        'line', (tester) async {
      await _pumpTile(
        tester,
        message: _factEditedMessage(),
        capabilities: const RoomCapabilities.request(),
      );

      expect(find.text(l10n.beaconRoomFactWhatChanged), findsOneWidget);
    });
  });

  group('BeaconRoomSurface passes host capabilities down to the room', () {
    final nowState = _state(
      messages: [_plainMessage()],
      roomState: BeaconRoomState(
        beaconId: 'b1',
        updatedAt: _createdAt,
        currentLine: _nowLine,
      ),
    );

    testWidgets('a Post host yields a room with no pinned NOW row and no '
        'Request actions', (tester) async {
      final host = _FakeRoomHost()
        ..capabilities = const RoomCapabilities.post();
      addTearDown(() async {
        final closing = host.close();
        await tester.pump();
        await closing;
      });
      await _pumpSurface(tester, host: host, roomState: nowState);

      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsNothing,
      );
      await _openActionsSheet(tester);
      expect(find.text(l10n.beaconRoomActionReply), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsNothing);
      expect(find.text(l10n.beaconRoomActionPinFact), findsNothing);
    });

    testWidgets('a Request host yields a room with the pinned NOW row and '
        'Request actions', (tester) async {
      final host = _FakeRoomHost()
        ..capabilities = const RoomCapabilities.request();
      addTearDown(() async {
        final closing = host.close();
        await tester.pump();
        await closing;
      });
      await _pumpSurface(tester, host: host, roomState: nowState);

      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsOneWidget,
      );
      await _openActionsSheet(tester);
      expect(find.text(l10n.beaconRoomActionTurnInto), findsOneWidget);
      expect(find.text(l10n.beaconRoomActionPinFact), findsOneWidget);
    });

    testWidgets('the room picks up capabilities the host changes later', (
      tester,
    ) async {
      final host = _FakeRoomHost()
        ..capabilities = const RoomCapabilities.post();
      addTearDown(() async {
        final closing = host.close();
        await tester.pump();
        await closing;
      });
      await _pumpSurface(tester, host: host, roomState: nowState);
      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsNothing,
      );

      host.capabilities = const RoomCapabilities.request();
      host.announce();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining(_nowLine, findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('BeaconRoomSurface host', () {
    testWidgets('rebuilds when the host announces a change', (tester) async {
      final host = _FakeRoomHost();
      final threadHost = ThreadHostCubit(
        beaconId: 'b1',
        roomCubitFactory:
            ({
              required String beaconId,
              String? threadItemId,
              DateTime? initialUnreadAnchorAt,
              RoomCapabilities capabilities = const RoomCapabilities.request(),
            }) => throw StateError('no room expected'),
      );
      // Unmount first: `ThreadHostCubit.close()` awaits `_switchTail`, a
      // plain `Future` born inside this test's FakeAsync zone; a bare await
      // on it from a teardown running after the zone has finished never
      // resumes even once it has genuinely settled (a known FakeAsync-zone
      // quirk), so race it with a timeout instead of awaiting it directly.
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final closing = [threadHost.close(), host.close()];
        await tester.pump();
        await Future.wait(closing);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: TenturaResponsiveScope(
              child: BlocProvider<ThreadsCubit>.value(
                value: _MockThreadsCubit(
                  const ThreadsState(
                    threads: [],
                    myUserId: 'me',
                    status: StateIsSuccess(),
                  ),
                ),
                child: BeaconRoomSurface(
                  host: host,
                  roomLease: BeaconRoomLease(host: threadHost),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(l10n.beaconRoomWaitingForApproval), findsNothing);

      host.isAdmissionBlocked = true;
      host.announce();
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);

      host.coordinationDeniesAdmission = true;
      host.announce();
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.beaconRoomNoAdmission), findsOneWidget);
    });
  });
}
