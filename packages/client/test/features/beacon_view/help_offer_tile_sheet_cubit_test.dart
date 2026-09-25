import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/help_offer_tile_sheet_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'help_offer_author_seen_test_support.dart'
    show kSteward, stewardParticipant;

FakeHelpOfferCoordinationRow _row({
  required String userId,
  int offerKind = 0,
  int status = 0,
  String message = 'I can help',
}) {
  final user = Profile(id: userId, displayName: 'Offerer');
  final now = DateTime.utc(2026, 9, 1);
  return (
    beaconId: 'b1',
    userId: userId,
    user: user,
    message: message,
    helpType: null,
    roleLabel: '',
    status: status,
    withdrawReason: null,
    createdAt: now,
    updatedAt: now,
    responseType: null,
    responseUpdatedAt: null,
    responseAuthorUserId: null,
    roomAccess: null,
    admissionAction: null,
    lastDeclineReason: null,
    lastRemoveReason: null,
    stakeState: 0,
    offerKind: offerKind,
    isDirectAuthorForward: false,
    authorSeenAt: null,
  );
}

class _FailAcceptCoordination extends FakeBeaconViewCoordinationRepository {
  _FailAcceptCoordination({required super.rows});

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
  }) async {
    throw StateError('accept failed');
  }
}

BeaconParticipant _stewardFor(String beaconId) =>
    stewardParticipant().copyWith(beaconId: beaconId);

class _HeldCoordination extends FakeBeaconViewCoordinationRepository {
  _HeldCoordination({required super.rows});

  final gate = Completer<DateTime>();

  @override
  Future<DateTime> markBeaconPeopleSeen(String beaconId) {
    peopleSeenBeaconIds.add(beaconId);
    return gate.future;
  }
}

class _ProbeCoordination extends FakeBeaconViewCoordinationRepository {
  _ProbeCoordination({required super.rows});

  void Function()? onMark;

  @override
  Future<DateTime> markBeaconPeopleSeen(String beaconId) {
    onMark?.call();
    return super.markBeaconPeopleSeen(beaconId);
  }
}

class _ThrowingPeopleSeenCoordination
    extends FakeBeaconViewCoordinationRepository {
  _ThrowingPeopleSeenCoordination({required super.rows});

  int attempts = 0;
  void Function()? onMark;

  @override
  Future<DateTime> markBeaconPeopleSeen(String beaconId) async {
    attempts++;
    onMark?.call();
    throw StateError('people seen failed');
  }
}

void main() {
  final author = Profile(id: 'author-1', displayName: 'Author');
  final offerer = Profile(id: 'offerer-1', displayName: 'Offerer');

  test('accept succeeds after load on open Request', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.open,
        author: author,
      );
    final coordination = FakeBeaconViewCoordinationRepository(
      rows: [_row(userId: offerer.id)],
    );
    final effects = FakeUiEffectPort();
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
      ),
      effects: effects,
    );

    await cubit.load();
    expect(cubit.canManageOffer, isTrue);
    expect(cubit.state.offer?.message, 'I can help');
    expect(await cubit.accept(), isTrue);
    expect(coordination.acceptHelpOfferCalls, [
      (beaconId: 'b1', offerUserId: offerer.id),
    ]);
    expect(effects.emitted.whereType<ShowError>(), isEmpty);

    await cubit.close();
  });

  test('load exposes personal note for respond sheet (#160)', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.open,
        author: author,
      );
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          rows: [
            _row(userId: offerer.id, message: 'I can sew the costume'),
          ],
        ),
      ),
      effects: FakeUiEffectPort(),
    );

    await cubit.load();
    expect(cubit.state.offer, isNotNull);
    expect(cubit.state.offer!.message, 'I can sew the costume');

    await cubit.close();
  });

  test('closed Request disables admit actions', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.closed,
        author: author,
      );
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          rows: [_row(userId: offerer.id)],
        ),
      ),
      effects: FakeUiEffectPort(),
    );

    await cubit.load();
    expect(cubit.canManageOffer, isFalse);
    expect(await cubit.accept(), isFalse);

    await cubit.close();
  });

  test('backup offer kind disables admit', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.open,
        author: author,
      );
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(
          rows: [_row(userId: offerer.id, offerKind: 1)],
        ),
      ),
      effects: FakeUiEffectPort(),
    );

    await cubit.load();
    expect(cubit.canManageOffer, isFalse);

    await cubit.close();
  });

  test('missing offer leaves no admit path', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.open,
        author: author,
      );
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(rows: const []),
      ),
      effects: FakeUiEffectPort(),
    );

    await cubit.load();
    expect(cubit.state.offer, isNull);
    expect(cubit.canManageOffer, isFalse);

    await cubit.close();
  });

  test('load error emits ShowError and keeps sheet state', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => throw StateError('boom');
    final effects = FakeUiEffectPort();
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(beaconRepo: beaconRepo),
      effects: effects,
    );

    await cubit.load();
    expect(cubit.state.loadError, isNotNull);
    expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    expect(cubit.canManageOffer, isFalse);

    await cubit.close();
  });

  test('mutation error emits ShowError and returns false', () async {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
        id: id,
        status: BeaconStatus.open,
        author: author,
      );
    final coordination = _FailAcceptCoordination(
      rows: [_row(userId: offerer.id)],
    );
    final effects = FakeUiEffectPort();
    final cubit = HelpOfferTileSheetCubit(
      beaconId: 'b1',
      offerUserId: offerer.id,
      myProfile: author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordination,
      ),
      effects: effects,
    );

    await cubit.load();
    expect(await cubit.accept(), isFalse);
    expect(effects.emitted.whereType<ShowError>(), hasLength(1));

    await cubit.close();
  });

  group('load marks People seen for moderators (P4.2)', () {
    HelpOfferTileSheetCubit build({
      required Profile viewer,
      required FakeBeaconViewCoordinationRepository coordination,
      List<BeaconParticipant> participants = const [],
      FakeUiEffectPort? effects,
    }) {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (id) async => Beacon.empty.copyWith(
          id: id,
          status: BeaconStatus.open,
          author: author,
        );
      return HelpOfferTileSheetCubit(
        beaconId: 'b1',
        offerUserId: offerer.id,
        myProfile: viewer,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: coordination,
          roomRepo: FakeBeaconViewRoomRepository(participants: participants),
        ),
        effects: effects ?? FakeUiEffectPort(),
      );
    }

    test('author: markPeopleSeen called once with the request id', () async {
      final coordination = FakeBeaconViewCoordinationRepository(
        rows: [_row(userId: offerer.id)],
      );
      final cubit = build(viewer: author, coordination: coordination);

      await cubit.load();

      expect(coordination.peopleSeenBeaconIds, ['b1']);
      await cubit.close();
    });

    test('steward: markPeopleSeen called once', () async {
      final coordination = FakeBeaconViewCoordinationRepository(
        rows: [_row(userId: offerer.id)],
      );
      final cubit = build(
        viewer: kSteward,
        coordination: coordination,
        participants: [_stewardFor('b1')],
      );

      await cubit.load();

      expect(cubit.state.isSteward, isTrue);
      expect(coordination.peopleSeenBeaconIds, ['b1']);
      await cubit.close();
    });

    test('helper: markPeopleSeen never called', () async {
      final coordination = FakeBeaconViewCoordinationRepository(
        rows: [_row(userId: offerer.id)],
      );
      final cubit = build(viewer: offerer, coordination: coordination);

      await cubit.load();

      expect(cubit.state.isAuthorOrSteward, isFalse);
      expect(coordination.peopleSeenBeaconIds, isEmpty);
      await cubit.close();
    });

    test(
      'markPeopleSeen runs only after the loaded state is emitted',
      () async {
        final coordination = _ProbeCoordination(
          rows: [_row(userId: offerer.id)],
        );
        final cubit = build(viewer: author, coordination: coordination);
        var loadedAtCall = <bool>[];
        coordination.onMark = () => loadedAtCall.add(cubit.state.isLoaded);

        await cubit.load();

        expect(coordination.peopleSeenBeaconIds, ['b1']);
        expect(loadedAtCall, [true]);
        await cubit.close();
      },
    );

    test('load awaits markPeopleSeen before completing', () async {
      final coordination = _HeldCoordination(
        rows: [_row(userId: offerer.id)],
      );
      final cubit = build(viewer: author, coordination: coordination);
      var done = false;
      final future = cubit.load().then((_) => done = true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(coordination.peopleSeenBeaconIds, ['b1']);
      expect(done, isFalse);

      coordination.gate.complete(DateTime.utc(2026, 9, 1));
      await future;
      expect(done, isTrue);
      await cubit.close();
    });

    test('author: failed fetch never calls markPeopleSeen', () async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => throw StateError('boom');
      final coordination = FakeBeaconViewCoordinationRepository(
        rows: [_row(userId: offerer.id)],
      );
      final cubit = HelpOfferTileSheetCubit(
        beaconId: 'b1',
        offerUserId: offerer.id,
        myProfile: author,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: coordination,
        ),
        effects: FakeUiEffectPort(),
      );

      await cubit.load();

      expect(cubit.state.loadError, isNotNull);
      expect(coordination.peopleSeenBeaconIds, isEmpty);
      await cubit.close();
    });

    test('steward: failed fetch never calls markPeopleSeen', () async {
      final coordination = FakeBeaconViewCoordinationRepository(
        enrichmentError: StateError('offers boom'),
        rows: [_row(userId: offerer.id)],
      );
      final cubit = build(
        viewer: kSteward,
        coordination: coordination,
        participants: [_stewardFor('b1')],
      );

      await cubit.load();

      expect(cubit.state.loadError, isNotNull);
      expect(coordination.peopleSeenBeaconIds, isEmpty);
      await cubit.close();
    });

    test('markPeopleSeen throwing causes no further emission', () async {
      final coordination = _ThrowingPeopleSeenCoordination(
        rows: [_row(userId: offerer.id)],
      );
      final effects = FakeUiEffectPort();
      final cubit = build(
        viewer: author,
        coordination: coordination,
        effects: effects,
      );
      final emitted = <HelpOfferTileSheetState>[];
      final sub = cubit.stream.listen(emitted.add);
      HelpOfferTileSheetState? stateAtCall;
      coordination.onMark = () {
        stateAtCall = cubit.state;
      };

      await cubit.load();
      await Future<void>.delayed(Duration.zero);

      expect(coordination.attempts, 1);
      expect(stateAtCall?.isLoaded, isTrue);
      expect(emitted.where((st) => st.isLoaded), [stateAtCall]);
      expect(emitted.last, stateAtCall);
      expect(cubit.state, stateAtCall);
      expect(cubit.state.offer?.message, 'I can help');
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
      await sub.cancel();
      await cubit.close();
    });
  });
}
