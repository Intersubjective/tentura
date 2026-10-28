import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'BfirstLoad';
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _displayStatus = BeaconDisplayStatusDto(
  beaconId: _beaconId,
  status: BeaconStatus.open,
  phase: BeaconCoordinationPhase.lookingForHelpers,
  suggestedAction: BeaconPhasePrimaryAction.offerHelp,
  slot2Kind: BeaconPhaseSlot2Kind.noOffersYet,
  tier: BeaconDisplayTier.coordination,
);

Beacon _beacon({String title = 'Request to load'}) => Beacon(
  id: _beaconId,
  title: title,
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

// The new public state property does not exist yet. Keep the tests runnable
// before codegen/implementation, with a descriptive assertion failure rather
// than a compile error. Never substitute an existing readiness flag here.
Object? _firstLoadDone(BeaconViewState state) {
  try {
    return (state as dynamic).firstLoadDone;
  } on NoSuchMethodError {
    return 'BeaconViewState.firstLoadDone is missing';
  }
}

Future<void> _until(
  bool Function() ready, {
  String reason = 'Request data must reach the Cubit',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<void> _waitForPrimaryReadiness(BeaconViewCubit cubit) async {
  await _until(
    () => _firstLoadDone(cubit.state) == true,
    reason:
        'Beacon, status and offers have returned, but firstLoadDone '
        'did not become true while room enrichment was pending '
        '(actual: ${_firstLoadDone(cubit.state)}).',
  );
  expect(_firstLoadDone(cubit.state), isTrue);
  expect(cubit.state.roomParticipantsLoaded, isFalse);
  expect(cubit.state.beaconContextLoaded, isFalse);
}

// Keep room enrichment pending until the test explicitly releases it. This
// separates primary readiness from completion of the full context fetch.
class _HeldRoom extends FakeBeaconViewRoomRepository {
  final result = Completer<List<BeaconParticipant>>();

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) =>
      result.future;

  void release() {
    if (!result.isCompleted) result.complete([]);
  }
}

FakeHelpOfferCoordinationRow _offer() => (
  beaconId: _beaconId,
  userId: _viewer.id,
  user: _viewer,
  message: 'I can help with this Request',
  helpType: null,
  roleLabel: null,
  status: 0,
  withdrawReason: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  editedAt: null,
  responseType: null,
  responseUpdatedAt: null,
  responseAuthorUserId: null,
  roomAccess: null,
  admissionAction: null,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: null,
);

class _HeldOffers extends FakeBeaconViewCoordinationRepository {
  final requested = Completer<void>();
  final result = Completer<List<FakeHelpOfferCoordinationRow>>();

  @override
  Future<List<FakeHelpOfferCoordinationRow>> fetchHelpOffersWithCoordination({
    required String beaconId,
  }) {
    if (!requested.isCompleted) requested.complete();
    return result.future;
  }
}

class _HeldStatus extends FakeBeaconDisplayRepository {
  final requested = Completer<void>();
  final result = Completer<List<BeaconDisplayStatusDto>>();

  @override
  Future<List<BeaconDisplayStatusDto>> fetchDisplayStatuses(
    List<String> beaconIds,
  ) {
    if (!requested.isCompleted) requested.complete();
    return result.future;
  }
}

void main() {
  group('Request first-load readiness', () {
    for (final lastSlice in ['status', 'offers']) {
      test(
        'waits for beacon, status and offers when $lastSlice arrive last',
        () async {
          final content = Completer<Beacon>();
          final offers = _HeldOffers();
          final display = _HeldStatus();
          final room = _HeldRoom();
          addTearDown(room.dispose);
          final repository = TrackingBeaconRepository()
            ..fetchByIdHandler = (_) => content.future;
          addTearDown(repository.dispose);
          final cubit = BeaconViewCubit(
            id: _beaconId,
            myProfile: _viewer,
            beaconViewCase: buildTestBeaconViewCase(
              beaconRepo: repository,
              coordinationRepo: offers,
              displayRepo: display,
              roomRepo: room,
            ),
            effects: FakeUiEffectPort(),
          );
          addTearDown(cubit.close);
          addTearDown(room.release);
          final beforeContent = cubit.state;

          content.complete(_beacon());
          await Future.wait([
            offers.requested.future,
            display.requested.future,
          ]);
          final beforeEnrichment = cubit.state;
          expect(beforeEnrichment.beacon.title, 'Request to load');

          if (lastSlice == 'status') {
            offers.result.complete([_offer()]);
            await _until(
              () => cubit.state.helpOffers.any(
                (offer) =>
                    offer.user.id == _viewer.id &&
                    offer.message == 'I can help with this Request',
              ),
              reason:
                  'The completed offers must be visible while status and '
                  'room enrichment are still pending.',
            );
          } else {
            display.result.complete([_displayStatus]);
            await _until(
              () => identical(cubit.state.displayStatus, _displayStatus),
              reason:
                  'The completed status must be visible while offers and '
                  'room enrichment are still pending.',
            );
          }
          final beforeLastSlice = cubit.state;
          expect(
            [
              beforeContent,
              beforeEnrichment,
              beforeLastSlice,
            ].map(_firstLoadDone),
            [false, false, false],
            reason:
                'Readiness must remain false after the earlier primary '
                'response is applied and the last primary response is pending.',
          );

          if (lastSlice == 'status') {
            display.result.complete([_displayStatus]);
          } else {
            offers.result.complete([_offer()]);
          }
          await _waitForPrimaryReadiness(cubit);
          expect(cubit.state.displayStatus, same(_displayStatus));
          expect(
            cubit.state.helpOffers.single.message,
            'I can help with this Request',
          );
          expect(
            [
              beforeContent,
              beforeEnrichment,
              beforeLastSlice,
              cubit.state,
            ].map(_firstLoadDone),
            [false, false, false, true],
            reason:
                'Primary slices determine readiness independently of the '
                'pending room participants.',
          );
        },
      );
    }

    test(
      'empty offers complete the first load before room enrichment',
      () async {
        final room = _HeldRoom();
        addTearDown(room.dispose);
        final repository = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon();
        addTearDown(repository.dispose);
        final cubit = BeaconViewCubit(
          id: _beaconId,
          myProfile: _viewer,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: repository,
            displayRepo: FakeBeaconDisplayRepository(rows: [_displayStatus]),
            roomRepo: room,
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        addTearDown(room.release);

        await _waitForPrimaryReadiness(cubit);

        expect(cubit.state.beacon.title, 'Request to load');
        expect(cubit.state.displayStatus, same(_displayStatus));
        expect(cubit.state.helpOffers, isEmpty);
        room.release();
        await _until(() => cubit.state.roomParticipantsLoaded);
        expect(_firstLoadDone(cubit.state), isTrue);
      },
    );

    test(
      'stays ready throughout a loading refresh and its new content',
      () async {
        final refreshContent = Completer<Beacon>();
        final room = _HeldRoom();
        addTearDown(room.dispose);
        final repository = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon();
        addTearDown(repository.dispose);
        final cubit = BeaconViewCubit(
          id: _beaconId,
          myProfile: _viewer,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: repository,
            displayRepo: FakeBeaconDisplayRepository(rows: [_displayStatus]),
            roomRepo: room,
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        addTearDown(room.release);
        await _waitForPrimaryReadiness(cubit);
        final states = <BeaconViewState>[cubit.state];
        final subscription = cubit.stream.listen(states.add);
        addTearDown(subscription.cancel);
        room.release();
        await _until(() => cubit.state.roomParticipantsLoaded);
        repository.fetchByIdHandler = (_) => refreshContent.future;

        // A user action triggers the public refresh path with isLoading set.
        final refresh = cubit.setBeaconStatus(BeaconStatus.enoughHelp);
        expect(cubit.state.isLoading, isTrue);
        states.add(cubit.state);
        await _until(() => repository.fetchByIdCalls == 2);
        refreshContent.complete(_beacon(title: 'Updated Request'));
        expect(await refresh, isTrue);
        await Future<void>.delayed(Duration.zero);
        states.add(cubit.state);

        expect(cubit.state.beacon.title, 'Updated Request');
        expect(cubit.state.isLoading, isFalse);
        expect(states.map(_firstLoadDone), everyElement(isTrue));
      },
    );

    test(
      'stays ready throughout a failed refresh and retains readable content',
      () async {
        final effects = FakeUiEffectPort();
        final room = _HeldRoom();
        addTearDown(room.dispose);
        final repository = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon();
        addTearDown(repository.dispose);
        final cubit = BeaconViewCubit(
          id: _beaconId,
          myProfile: _viewer,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: repository,
            displayRepo: FakeBeaconDisplayRepository(rows: [_displayStatus]),
            roomRepo: room,
          ),
          effects: effects,
        );
        addTearDown(cubit.close);
        addTearDown(room.release);
        await _waitForPrimaryReadiness(cubit);
        final states = <BeaconViewState>[cubit.state];
        final subscription = cubit.stream.listen(states.add);
        addTearDown(subscription.cancel);
        room.release();
        await _until(() => cubit.state.roomParticipantsLoaded);
        final failure = StateError('Connection lost during refresh');
        final refreshContent = Completer<Beacon>();
        repository.fetchByIdHandler = (_) => refreshContent.future;

        final refresh = cubit.setBeaconStatus(BeaconStatus.enoughHelp);
        await _until(() => states.any((state) => state.isLoading));
        refreshContent.completeError(failure);
        await refresh;
        // The action has finished emitting; drain its queued stream events
        // before checking every observed state, including any transient reset.
        await Future<void>.delayed(Duration.zero);
        states.add(cubit.state);

        expect(repository.fetchByIdCalls, 2);
        expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
        expect(cubit.state.beacon.title, 'Request to load');
        expect(cubit.state.beaconUnavailable, isFalse);
        expect(states.map(_firstLoadDone), everyElement(isTrue));
      },
    );
  });
}
