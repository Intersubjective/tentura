import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/threads_list.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';

class _MockThreadsCubit extends Mock implements ThreadsCubit {
  _MockThreadsCubit(this._state);

  final ThreadsState _state;

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => Stream<ThreadsState>.value(_state);
}

class _SpyBeaconViewCubit extends Mock implements BeaconViewCubit {
  @override
  BeaconViewState get state => _state;

  final BeaconViewState _state;

  _SpyBeaconViewCubit(this._state);

  @override
  Stream<BeaconViewState> get stream => Stream<BeaconViewState>.value(_state);
}

const _kBeaconId = 'B-threads-list';
const _kAuthorId = 'author-1';
const _kOtherId = 'other-1';
const _kMyId = 'author-1';
final _kNow = DateTime.utc(2026, 8, 14, 12, 30);

RequestThread _generalThread({
  int unreadCount = 0,
  ThreadMessagePreview? preview,
  String? authorId,
}) =>
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      unreadCount: unreadCount,
      messageCount: 3,
      lastMessageAt: _kNow.subtract(const Duration(minutes: 5)),
      lastMessageAuthorId: authorId ?? _kOtherId,
      lastMessagePreview: preview ??
          const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.text,
            excerpt: 'General hello',
          ),
    );

BeaconViewState _beaconViewState({
  List<BeaconParticipant> participants = const [],
  bool waitingForAdmission = false,
}) {
  final author = const Profile(id: 'other-author', displayName: 'Other');
  return BeaconViewState(
    beacon: Beacon(
      id: _kBeaconId,
      title: 'Test request',
      author: author,
      createdAt: _kNow,
      updatedAt: _kNow,
    ),
    myProfile: const Profile(id: _kMyId, displayName: 'Me'),
    roomParticipants: participants,
    roomParticipantsLoaded: true,
    isHelpOffered: waitingForAdmission,
  );
}

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconHierarchyCase _hierarchyCase(FakeBeaconHierarchyRepositoryPort port) =>
    BeaconHierarchyCase(
      port,
      BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      _NoopBeaconWritePort(),
      InMemoryBeaconChildCommandStore(),
    );

Widget _wrapThreadsList({
  required ThreadsCubit threadsCubit,
  required BeaconViewState beaconState,
  required VoidCallback onOpenGeneral,
  VoidCallback? onSwitchToPeopleTab,
  FakeBeaconHierarchyRepositoryPort? hierarchyPort,
  Size size = const Size(400, 900),
}) {
  final port = hierarchyPort ??
      FakeBeaconHierarchyRepositoryPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: false,
          canCreateChild: false,
        ),
      );
  final hierarchyCubit = BeaconHierarchyCubit(
    beaconId: beaconState.beacon.id,
    hierarchyCase: _hierarchyCase(port),
  );
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<ThreadsCubit>.value(value: threadsCubit),
            BlocProvider<BeaconViewCubit>.value(
              value: _SpyBeaconViewCubit(beaconState),
            ),
            BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
          ],
          child: ThreadsList(
            beaconState: beaconState,
            onOpenGeneral: onOpenGeneral,
            onSwitchToPeopleTab: onSwitchToPeopleTab,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders General row with title and preview', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    var opened = 0;
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenGeneral: () => opened++,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.threadGeneralTitle), findsOneWidget);
    expect(find.textContaining('General hello'), findsOneWidget);
    expect(
      find.byKey(TestIds.key(TestIds.requestThread(RequestThread.generalId))),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(TestIds.key(TestIds.requestThread(RequestThread.generalId))),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('General face pile tap does not open thread', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    var opened = 0;
    var peopleTabTaps = 0;
    final beaconState = _beaconViewState().copyWith(
      helpOffers: [
        TimelineHelpOffer(
          user: const Profile(id: _kOtherId, displayName: 'Helper'),
          message: 'help',
          createdAt: _kNow,
          updatedAt: _kNow,
        ),
      ],
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: beaconState,
        onOpenGeneral: () => opened++,
        onSwitchToPeopleTab: () => peopleTabTaps++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BeaconInvolvedPeopleFacePile), findsOneWidget);
    await tester.tap(find.byType(BeaconInvolvedPeopleFacePile));
    await tester.pumpAndSettle();
    expect(peopleTabTaps, 1);
    expect(opened, 0);
  });

  testWidgets('non-admitted viewer hides child requests section', (tester) async {
    final threadsState = ThreadsState(
      threads: [_generalThread()],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(waitingForAdmission: true),
        onOpenGeneral: () {},
        hierarchyPort: FakeBeaconHierarchyRepositoryPort(
          capabilities: const BeaconHierarchyCapabilities(
            canListChildren: true,
            canCreateChild: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconChildRequestsTitle), findsNothing);
    expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
  });

  testWidgets('never renders raw user id in preview author', (tester) async {
    const rawId = 'Uraw000000001';
    final threadsState = ThreadsState(
      threads: [
        _generalThread(
          authorId: rawId,
          preview: const ThreadMessagePreview(
            kind: ThreadMessagePreviewKind.text,
            excerpt: 'secret preview',
          ),
        ),
      ],
      myUserId: _kMyId,
      status: const StateIsSuccess(),
    );
    await tester.pumpWidget(
      _wrapThreadsList(
        threadsCubit: _MockThreadsCubit(threadsState),
        beaconState: _beaconViewState(),
        onOpenGeneral: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(rawId), findsNothing);
    expect(find.textContaining('secret preview'), findsOneWidget);
  });
}
