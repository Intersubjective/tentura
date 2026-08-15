import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
  const beaconId = 'Bfacts01';
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  Beacon readableBeacon() => Beacon(
    id: beaconId,
    title: 'Facts beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconFactCard fact({
    required String id,
    required DateTime createdAt,
    String pinnedBy = 'other',
  }) =>
      BeaconFactCard(
        id: id,
        beaconId: beaconId,
        factText: id,
        visibility: BeaconFactCardVisibilityBits.public,
        pinnedBy: pinnedBy,
        createdAt: createdAt,
        status: BeaconFactCardStatusBits.active,
      );

  BeaconViewCubit cubitFor({
    required BeaconViewCase case_,
  }) =>
      BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: case_,
        coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
        effects: FakeUiEffectPort(),
      );

  test('constructor hydrates seenAt from the case', () {
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
    );
    case_.markPinnedFactsSeen(
      beaconId: beaconId,
      userId: myProfile.id,
      facts: [fact(id: 'a', createdAt: t1)],
    );

    final cubit = cubitFor(case_: case_);
    addTearDown(cubit.close);

    expect(cubit.state.pinnedFactsSeenAt, t1);
  });

  test('first fetch baselines current max; later others increment +N', () async {
    final factsRepo = FakeBeaconViewFactCardRepository(
      cards: [fact(id: 'old', createdAt: t0)],
    );
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => readableBeacon();
    final case_ = buildTestBeaconViewCase(
      beaconRepo: beaconRepo,
      factCardsRepo: factsRepo,
    );
    final cubit = cubitFor(case_: case_);
    addTearDown(cubit.close);

    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

    expect(cubit.state.pinnedFactsSeenAt, t0);
    expect(
      pinnedFactsNewCount(
        facts: cubit.state.factCards,
        seenAt: cubit.state.pinnedFactsSeenAt,
        viewerUserId: myProfile.id,
      ),
      0,
    );

    factsRepo.cards = [
      fact(id: 'old', createdAt: t0),
      fact(id: 'new', createdAt: t1),
    ];
    beaconRepo.emitInvalidation(beaconId);
    await pumpUntil(
      cubit.stream,
      () => cubit.state.factCards.length == 2,
    );

    expect(
      pinnedFactsNewCount(
        facts: cubit.state.factCards,
        seenAt: cubit.state.pinnedFactsSeenAt,
        viewerUserId: myProfile.id,
      ),
      1,
    );
  });

  test('in-flight fetch does not clobber markSeen', () async {
    final hold = Completer<void>();
    final factsRepo = FakeBeaconViewFactCardRepository(
      cards: [fact(id: 'a', createdAt: t1)],
      listHold: hold,
    );
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
      factCardsRepo: factsRepo,
    );
    final cubit = cubitFor(case_: case_);
    addTearDown(cubit.close);

    await pumpUntilCondition(() => factsRepo.listCalls >= 1);
    cubit.markPinnedFactsSeen();
    expect(case_.pinnedFactsSeenAt(beaconId, myProfile.id), epoch);

    hold.complete();
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

    expect(cubit.state.pinnedFactsSeenAt, epoch);
    expect(case_.pinnedFactsSeenAt(beaconId, myProfile.id), epoch);
  });

  test('removeFact hits the case repository', () async {
    final factsRepo = FakeBeaconViewFactCardRepository(
      cards: [fact(id: 'f1', createdAt: t0)],
    );
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
      factCardsRepo: factsRepo,
    );
    final cubit = cubitFor(case_: case_);
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

    await cubit.removeFact(factCardId: 'f1');

    expect(factsRepo.removedIds, ['f1']);
  });

  test('correctFact hits the case repository', () async {
    final factsRepo = FakeBeaconViewFactCardRepository(
      cards: [fact(id: 'f1', createdAt: t0)],
    );
    final case_ = buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => readableBeacon(),
      factCardsRepo: factsRepo,
    );
    final cubit = cubitFor(case_: case_);
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

    await cubit.correctFact(factCardId: 'f1', newText: 'edited');

    expect(factsRepo.correctedIds, ['f1']);
  });
}
