// #484: after «Make live without sending» the new Request's room opened
// with no message composer when the room's thread list query failed (e.g.
// "Constellation database busy"); only a reload brought the composer back.
// Request rooms are General-only, so the room — and its composer — must not
// depend on that list: a failed list still opens the General room.

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/beacon/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import 'support/room_body_harness.dart';

const _author = Profile(id: 'me', displayName: 'Me');

final _busy = Exception('Constellation database busy');

/// The author alone in a writable, empty room: what a Request made live
/// without sending looks like.
RoomState _freshRoom() => roomBodyState().copyWith(
  participants: [
    roomBodyAdmittedParticipant(
      beaconId: 'b1',
      profile: _author,
      role: BeaconParticipantRoleBits.author,
    ),
  ],
  participantsLoaded: true,
);

/// The thread list as `ThreadsCubit.fetch` leaves it after the query threw.
ThreadsState _failedList() => ThreadsState(
  myUserId: _author.id,
  loadError: _busy,
);

class _StubRouter extends Mock implements StackRouter {}

class _FakeRoomHost implements RoomHost {
  final _changes = StreamController<void>.broadcast();

  @override
  bool isAdmissionBlocked = false;

  @override
  bool coordinationDeniesAdmission = false;

  @override
  RoomCapabilities capabilities = const RoomCapabilities.request();

  @override
  String get beaconId => 'b1';

  @override
  Profile get author => _author;

  @override
  BeaconStatus get status => BeaconStatus.open;

  @override
  Stream<void> get changes => _changes.stream;

  /// The owner approved the viewer: the host flips and notifies.
  void admit() {
    isAdmissionBlocked = false;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}

/// Thread list cubit whose state the test drives; `fetch` is a no-op, so
/// nothing but the surface itself can bring the room up.
class _ScriptedThreadsCubit extends Mock implements ThreadsCubit {
  _ScriptedThreadsCubit(this._state);

  ThreadsState _state;
  final _controller = StreamController<ThreadsState>.broadcast();

  @override
  ThreadsState get state => _state;

  @override
  Stream<ThreadsState> get stream => _controller.stream;

  void push(ThreadsState next) {
    _state = next;
    _controller.add(next);
  }

  /// Every `fetch` the surface asked for (the cubit itself does nothing).
  final fetches = <bool>[];

  @override
  Future<void> fetch({bool silent = false}) async => fetches.add(silent);

  @override
  Future<void> close() => _controller.close();
}

/// Counts what the surface asked of the room: every room cubit the host
/// built and every `load` (the room's own reads).
class _RoomReads {
  int created = 0;
  int loads = 0;
}

class _SurfaceRoomCubit extends RoomBodyHarnessCubit {
  _SurfaceRoomCubit(super.initial, {this.reads});

  final _RoomReads? reads;

  var _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async => _closed = true;

  @override
  Future<void> load() async {
    reads?.loads++;
  }

  @override
  void prepareThreadScroll({String? messageId, String? coordinationItemId}) {}
}

Future<void> _pumpSurface(
  WidgetTester tester, {
  required _FakeRoomHost host,
  required _ScriptedThreadsCubit threads,
  _RoomReads? reads,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  final profileCubit = RoomBodyHarnessProfileCubit(_author);
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

  RoomCubit roomFactory({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
    RoomCapabilities? capabilities,
  }) {
    reads?.created++;
    return _SurfaceRoomCubit(_freshRoom(), reads: reads);
  }

  final threadHost = ThreadHostCubit(
    beaconId: 'b1',
    roomCubitFactory: roomFactory,
  );
  // Same teardown order as room_capabilities_widget_test: unmount, flush the
  // lease's deferred drop, then close the host.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final closing = threadHost.close();
    await tester.pump();
    await closing;
    await threads.close();
    final hostClosing = host.close();
    await tester.pump();
    await hostClosing;
  });

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
                BlocProvider<ThreadsCubit>.value(value: threads),
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
}

/// Bounded pumping: the room hosts animations that never settle.
Future<void> _pumpUntilRoomBody(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BeaconRoomBody).evaluate().isNotEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  final l10n = lookupL10n(const Locale('en'));

  group('#484 a failed thread list still opens the room with a composer', () {
    testWidgets('list already failed when the room opens', (tester) async {
      final host = _FakeRoomHost();
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads);
      await _pumpUntilRoomBody(tester);

      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(find.byType(BeaconRoomComposer), findsOneWidget);
      // Writable: the author can send the first message.
      expect(find.text(l10n.beaconRoomMessageReadOnlyHint), findsNothing);
      // Not the old dead end.
      expect(find.text(l10n.beaconItemsEmptyPlaceholder), findsNothing);
    });

    testWidgets('list fails while the room is opening (no reload)', (
      tester,
    ) async {
      final host = _FakeRoomHost();
      final threads = _ScriptedThreadsCubit(
        ThreadsState(myUserId: _author.id, status: const StateIsLoading()),
      );
      await _pumpSurface(tester, host: host, threads: threads);
      await tester.pump(const Duration(milliseconds: 50));

      threads.push(_failedList());
      await _pumpUntilRoomBody(tester);

      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(find.byType(BeaconRoomComposer), findsOneWidget);
      expect(find.text(l10n.beaconItemsEmptyPlaceholder), findsNothing);
    });

    testWidgets('guard: a viewer waiting for admission gets no composer', (
      tester,
    ) async {
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads);
      await _pumpUntilRoomBody(tester);

      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
      expect(find.byType(BeaconRoomComposer), findsNothing);
      expect(find.byType(BeaconRoomBody), findsNothing);
    });

    // The server omits the General thread to viewers who are not room
    // members, so a SUCCESSFUL empty list is a real "no room for you" answer.
    // The synthetic General fallback is for a failed list (loadError) only.
    testWidgets(
      'guard: empty list without loadError (non-member) gets no composer',
      (tester) async {
        final host = _FakeRoomHost();
        final threads = _ScriptedThreadsCubit(
          ThreadsState(myUserId: _author.id),
        );
        await _pumpSurface(tester, host: host, threads: threads);
        await _pumpUntilRoomBody(tester);

        expect(threads.state.loadError, isNull);
        expect(threads.state.isSuccess, isTrue);
        expect(find.byType(BeaconRoomComposer), findsNothing);
        expect(find.byType(BeaconRoomBody), findsNothing);
        expect(find.text(l10n.beaconItemsEmptyPlaceholder), findsOneWidget);
      },
    );
  });

  // PR #608 review (ichorid): the stand-in General is for a Request viewer
  // who may be in the room. A viewer the admission gate keeps out gets no
  // room at all when the list fails: no room cubit is built and nothing of
  // the room is read; the admission line shows exactly as before #484.
  group('#484 a failed list opens no stand-in room for a blocked viewer', () {
    testWidgets('waiting for approval: no room built, no room reads', (
      tester,
    ) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      expect(host.capabilities.coordinationItems, isTrue); // a Request room
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await _pumpUntilRoomBody(tester);

      expect(reads.created, 0);
      expect(reads.loads, 0);
      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
      expect(find.byType(BeaconRoomBody), findsNothing);
      expect(find.byType(BeaconRoomComposer), findsNothing);
    });

    testWidgets('denied: no room built, no room reads', (tester) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()
        ..isAdmissionBlocked = true
        ..coordinationDeniesAdmission = true;
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await _pumpUntilRoomBody(tester);

      expect(reads.created, 0);
      expect(reads.loads, 0);
      expect(find.text(l10n.beaconRoomNoAdmission), findsOneWidget);
      expect(find.byType(BeaconRoomBody), findsNothing);
      expect(find.byType(BeaconRoomComposer), findsNothing);
    });

    testWidgets('list fails while opening for a waiting viewer: no room', (
      tester,
    ) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      final threads = _ScriptedThreadsCubit(
        ThreadsState(myUserId: _author.id, status: const StateIsLoading()),
      );
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await tester.pump(const Duration(milliseconds: 50));

      threads.push(_failedList());
      await _pumpUntilRoomBody(tester);

      expect(reads.created, 0);
      expect(reads.loads, 0);
      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
    });

    // Request-only: a Post room (no coordination items) never gets the
    // stand-in either; its failed list keeps the plain placeholder.
    testWidgets('guard: a Post room with a failed list builds no room', (
      tester,
    ) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()
        ..capabilities = const RoomCapabilities.post();
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await _pumpUntilRoomBody(tester);

      expect(reads.created, 0);
      expect(find.byType(BeaconRoomComposer), findsNothing);
      expect(find.text(l10n.beaconItemsEmptyPlaceholder), findsOneWidget);
    });
  });

  // #609 (from #484): a viewer admitted while the thread list is failed
  // stayed on a spinner until the room was reopened — the room was set up
  // once, while the viewer was still blocked, and never again; and nothing
  // retried the failed list.
  group('#609 a viewer admitted while the list is failed gets the room', () {
    testWidgets('admitted with the list still failed: room and composer', (
      tester,
    ) async {
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads);
      await _pumpUntilRoomBody(tester);
      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);

      host.admit();
      await _pumpUntilRoomBody(tester);

      expect(find.text(l10n.beaconRoomWaitingForApproval), findsNothing);
      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(find.byType(BeaconRoomComposer), findsOneWidget);
    });

    testWidgets('admission retries the failed thread list', (tester) async {
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads);
      await _pumpUntilRoomBody(tester);
      expect(threads.fetches, isEmpty);

      host.admit();
      await _pumpUntilRoomBody(tester);

      expect(threads.fetches, isNotEmpty);
      // A background retry: the room already shown does not blink.
      expect(threads.fetches, everyElement(isTrue));
    });

    testWidgets('the retried list brings General: the room opens on it', (
      tester,
    ) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      // Non-member: the server omits General, so the list is empty.
      final threads = _ScriptedThreadsCubit(ThreadsState(myUserId: _author.id));
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await _pumpUntilRoomBody(tester);
      expect(reads.created, 0);

      host.admit();
      await tester.pump();
      threads.push(
        ThreadsState(
          myUserId: _author.id,
          threads: const [
            RequestThread(
              threadId: RequestThread.generalId,
              kind: RequestThreadKind.general,
            ),
          ],
        ),
      );
      await _pumpUntilRoomBody(tester);

      expect(find.byType(BeaconRoomBody), findsOneWidget);
      expect(find.byType(BeaconRoomComposer), findsOneWidget);
    });

    testWidgets('guard: still waiting — no retry, no room', (tester) async {
      final reads = _RoomReads();
      final host = _FakeRoomHost()..isAdmissionBlocked = true;
      final threads = _ScriptedThreadsCubit(_failedList());
      await _pumpSurface(tester, host: host, threads: threads, reads: reads);
      await _pumpUntilRoomBody(tester);

      // An unrelated host change while still blocked.
      host._changes.add(null);
      threads.push(_failedList());
      await _pumpUntilRoomBody(tester);

      expect(threads.fetches, isEmpty);
      expect(reads.created, 0);
      expect(find.text(l10n.beaconRoomWaitingForApproval), findsOneWidget);
    });
  });
}
