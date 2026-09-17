import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/help_offer_tile_sheet_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

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
}
