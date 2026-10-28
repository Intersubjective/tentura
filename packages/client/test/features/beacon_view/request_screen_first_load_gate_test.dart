import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_screen_harness.dart';

const _beaconId = 'BscreenFirstLoad';
const _message = 'The ladder is ready for collection';

// The screen contract includes a public RoomState.firstLoadDone latch. Keep
// this test compilable until that property exists, and report its absence as
// an assertion failure instead of substituting status or secondary flags.
Object? _roomFirstLoadDone(RoomState state) {
  try {
    return (state as dynamic).firstLoadDone;
    // ignore: avoid_catching_errors -- the missing getter is the failure.
  } on NoSuchMethodError {
    return 'RoomState.firstLoadDone is missing';
  }
}

int _gateSpinnerCount() => find
    .descendant(
      of: find.byType(TenturaFirstLoadGate),
      matching: find.byType(CircularProgressIndicator),
    )
    .evaluate()
    .length;

/// Loading indicators the screen paints on its own, outside the shared gate.
int _screenOwnSpinnerCount() =>
    find.byType(CircularProgressIndicator).evaluate().length -
    _gateSpinnerCount() +
    find.byType(CupertinoActivityIndicator).evaluate().length;

({int gateSpinners, int screenSpinners, int bodies, int messages})
_visibleFrame() => (
  gateSpinners: _gateSpinnerCount(),
  screenSpinners: _screenOwnSpinnerCount(),
  bodies: find.byType(BeaconNowSurface).evaluate().length,
  messages: find.textContaining(_message, findRichText: true).evaluate().length,
);

/// Holds the actual repository reads, rather than prescribing a readiness
/// implementation on the room state. Both cubits run their normal load paths.
class _RequestLoad {
  _RequestLoad() {
    loaded = beaconViewHarnessAuthorState(beaconId: _beaconId);
    beaconRepository = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) => beaconResponse.future;
    roomRepository =
        FakeBeaconThreadsRepository(
            userId: loaded.myProfile.id,
          )
          ..fetchMessagesCompleter = roomResponse
          ..messages = [
            RoomMessage(
              id: 'MreadyForCollection',
              beaconId: _beaconId,
              authorId: loaded.myProfile.id,
              author: loaded.myProfile,
              body: _message,
              createdAt: kBeaconViewHarnessNow,
            ),
          ];
    beaconCubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: loaded.myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepository,
      ),
      effects: FakeUiEffectPort(),
    );
    host = ThreadHostCubit(
      beaconId: _beaconId,
      roomCubitFactory:
          ({
            required beaconId,
            threadItemId,
            initialUnreadAnchorAt,
            capabilities = const RoomCapabilities.request(),
          }) => RoomCubit(
            beaconId: beaconId,
            threadItemId: threadItemId,
            initialUnreadAnchorAt: initialUnreadAnchorAt,
            capabilities: capabilities,
            beaconRoomCase: roomCubitMakeCase(roomRepository),
            coordinationItemRoomSync: itemSync,
            presenceRepository: roomCubitFakePresenceRepository(),
            effects: FakeUiEffectPort(),
          ),
    );
  }

  late final BeaconViewState loaded;
  late final TrackingBeaconRepository beaconRepository;
  late final FakeBeaconThreadsRepository roomRepository;
  late final BeaconViewCubit beaconCubit;
  late final ThreadHostCubit host;
  final beaconResponse = Completer<Beacon>();
  final roomResponse = Completer<void>();
  final itemSync = CoordinationItemRoomSync();
  BeaconViewHarness? harness;

  void finishBeacon() {
    if (!beaconResponse.isCompleted) beaconResponse.complete(loaded.beacon);
  }

  void finishRoom() {
    if (!roomResponse.isCompleted) roomResponse.complete();
  }

  Future<void> pump(WidgetTester tester) async {
    harness = await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessExpanded,
      beaconState: loaded,
      beaconViewCubit: beaconCubit,
      threadsState: beaconViewHarnessThreadsState(),
      host: host,
      viewTab: 'now',
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    finishBeacon();
    finishRoom();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await host.close();
      await beaconCubit.close();
      await harness?.threadsCubit.close();
      await beaconRepository.dispose();
      await roomRepository.dispose();
      await itemSync.dispose();
    });
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  // Stay well inside the gate's 2.5 s escape timeout: it must be readiness
  // that reveals the content in these tests, not the timeout.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  fail(reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(unregisterBeaconViewHarnessGetIt);

  group('Request screen first load', () {
    testWidgets(
      'waits for the room before revealing the body and keeps it during refresh',
      (tester) async {
        final load = _RequestLoad();
        try {
          await load.pump(tester);
          load.finishBeacon();
          await _pumpUntil(
            tester,
            () =>
                load.beaconCubit.state.firstLoadDone &&
                load.roomRepository.fetchMessagesCallCount > 0,
            reason: 'Request primary data must finish while room is pending',
          );
          expect(load.host.roomCubit!.state.isLoading, isTrue);
          final room = load.host.roomCubit!;
          final pendingReadiness = (
            beacon: load.beaconCubit.state.firstLoadDone,
            room: _roomFirstLoadDone(room.state),
          );
          await tester.pump(const Duration(milliseconds: 160));

          // Capture the pending frame so the release and refresh phases run
          // even against the old screen which exposes its body too early.
          final pendingFrame = _visibleFrame();

          // Cached/realtime messages and secondary slices may be available
          // before the initial snapshot finishes. Drive an idle frame with
          // those values: neither status nor populated rows replace the latch.
          room.emit(
            room.state.copyWith(
              status: const StateIsSuccess(),
              messages: [...load.roomRepository.messages],
              participantsLoaded: true,
              readWatermarksLoaded: true,
            ),
          );
          await tester.pump();
          expect(room.state.isLoading, isFalse);
          final idleRoomReadiness = _roomFirstLoadDone(room.state);
          final idleRoomFrame = _visibleFrame();

          load.finishRoom();
          await _pumpUntil(
            tester,
            () =>
                room.state.messages.isNotEmpty && room.state.roomState != null,
            reason: 'The released room response must reach the real room cubit',
          );
          await _pumpUntil(
            tester,
            () => find
                .textContaining(_message, findRichText: true)
                .evaluate()
                .isNotEmpty,
            reason: 'The loaded discussion must paint its seeded message',
          );
          expect(find.byType(BeaconNowSurface), findsOneWidget);
          expect(
            find.textContaining(_message, findRichText: true),
            findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          final loadedRoomReadiness = _roomFirstLoadDone(room.state);

          final refreshResponse = Completer<void>();
          load.roomRepository.fetchMessagesCompleter = refreshResponse;
          final refresh = room.reloadMessages();
          Object? refreshingRoomReadiness;
          try {
            await tester.pump();
            expect(room.state.isLoading, isTrue);
            refreshingRoomReadiness = _roomFirstLoadDone(room.state);
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(BeaconNowSurface), findsOneWidget);
            expect(
              find.textContaining(_message, findRichText: true),
              findsOneWidget,
            );
            expect(find.byType(CircularProgressIndicator), findsNothing);
          } finally {
            refreshResponse.complete();
            await refresh;
          }
          await tester.pump();
          expect(
            find.textContaining(_message, findRichText: true),
            findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);

          final beaconRefreshResponse = Completer<Beacon>();
          final beaconReads = load.beaconRepository.fetchByIdCalls;
          load.beaconRepository.fetchByIdHandler = (_) =>
              beaconRefreshResponse.future;
          load.beaconRepository.emitInvalidation(_beaconId);
          try {
            await _pumpUntil(
              tester,
              () => load.beaconRepository.fetchByIdCalls > beaconReads,
              reason: 'The realtime hint must start a Request refresh',
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(find.byType(BeaconNowSurface), findsOneWidget);
            expect(
              find.textContaining(_message, findRichText: true),
              findsOneWidget,
            );
            expect(find.byType(CircularProgressIndicator), findsNothing);
          } finally {
            beaconRefreshResponse.complete(
              load.loaded.beacon.copyWith(title: 'Collection moved to Friday'),
            );
          }
          await _pumpUntil(
            tester,
            () => find.text('Collection moved to Friday').evaluate().isNotEmpty,
            reason: 'The refreshed Request title must appear in place',
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);

          expect(
            (
              initial: pendingReadiness,
              idleRoom: idleRoomReadiness,
              loadedRoom: loadedRoomReadiness,
              refreshingRoom: refreshingRoomReadiness,
            ),
            (
              initial: (beacon: true, room: false),
              idleRoom: false,
              loadedRoom: true,
              refreshingRoom: true,
            ),
            reason:
                'The screen combines the Beacon and room first-load latches; '
                'room status and secondary-slice readiness are independent, '
                'and a refresh must never reset either latch.',
          );
          expect(
            pendingFrame,
            (gateSpinners: 1, screenSpinners: 0, bodies: 0, messages: 0),
            reason:
                'Before the room first loads, the shared gate must show one '
                'spinner and withhold the Request body even though Beacon '
                'primary data is already loaded.',
          );
          expect(
            idleRoomFrame,
            (gateSpinners: 1, screenSpinners: 0, bodies: 0, messages: 0),
            reason:
                'An idle room with its first-load latch still false must '
                'not let the screen reveal its body.',
          );
        } finally {
          await load.dispose(tester);
        }
      },
    );

    testWidgets(
      'shows only the shared gate spinner, after 150 ms, while the Request '
      'itself is still loading',
      (tester) async {
        final load = _RequestLoad();
        try {
          // The shared screen harness advances 50 ms after mounting.
          await load.pump(tester);

          // This is the state in which the screen used to paint its own
          // centered spinner: the Request is loading and nothing is cached.
          final beaconState = load.beaconCubit.state;
          expect(beaconState.firstLoadDone, isFalse);
          expect(beaconState.isLoading, isTrue);
          expect(beaconState.beaconContentLoaded, isFalse);
          expect(beaconState.timeline, isEmpty);
          expect(beaconState.helpOffers, isEmpty);

          final earlyFrame = _visibleFrame();
          await tester.pump(const Duration(milliseconds: 99));
          final beforeDelayFrame = _visibleFrame();
          await tester.pump(const Duration(milliseconds: 2));
          final afterDelayFrame = _visibleFrame();

          // Keep the Request pending for most of the escape window: at no
          // sampled frame may the screen paint a spinner of its own.
          var maxScreenSpinners = 0;
          var minGateSpinners = 1;
          for (var i = 0; i < 200; i++) {
            await tester.pump(const Duration(milliseconds: 10));
            final frame = _visibleFrame();
            if (frame.screenSpinners > maxScreenSpinners) {
              maxScreenSpinners = frame.screenSpinners;
            }
            if (frame.gateSpinners < minGateSpinners) {
              minGateSpinners = frame.gateSpinners;
            }
          }
          expect(load.beaconCubit.state.firstLoadDone, isFalse);

          expect(
            (
              early: earlyFrame,
              beforeDelay: beforeDelayFrame,
              afterDelay: afterDelayFrame,
              maxScreenSpinners: maxScreenSpinners,
              minGateSpinners: minGateSpinners,
            ),
            (
              early: (
                gateSpinners: 0,
                screenSpinners: 0,
                bodies: 0,
                messages: 0,
              ),
              beforeDelay: (
                gateSpinners: 0,
                screenSpinners: 0,
                bodies: 0,
                messages: 0,
              ),
              afterDelay: (
                gateSpinners: 1,
                screenSpinners: 0,
                bodies: 0,
                messages: 0,
              ),
              maxScreenSpinners: 0,
              minGateSpinners: 1,
            ),
            reason:
                'While the Request is loading, the only spinner must be the '
                'shared first-load gate spinner, delayed by 150 ms; the '
                "screen's own immediate centered spinner must be gone.",
          );

          load
            ..finishBeacon()
            ..finishRoom();
          await _pumpUntil(
            tester,
            () => find
                .textContaining(_message, findRichText: true)
                .evaluate()
                .isNotEmpty,
            reason: 'The Request must reveal its discussion once both load',
          );
          expect(find.byType(BeaconNowSurface), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
        } finally {
          await load.dispose(tester);
        }
      },
    );
  });
}
