import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';

import 'beacon_view_case_test_support.dart';

BeaconFactCard _fact({
  required String id,
  required DateTime createdAt,
  DateTime? updatedAt,
}) =>
    BeaconFactCard(
      id: id,
      beaconId: 'b1',
      factText: id,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'other',
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: BeaconFactCardStatusBits.active,
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  test('watermark keys are per user and beacon', () {
    final case_ = buildTestBeaconViewCase();
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'a', createdAt: t0)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u2',
      facts: [_fact(id: 'b', createdAt: t1)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b2',
      userId: 'u1',
      facts: [_fact(id: 'c', createdAt: t1)],
    );

    expect(case_.pinnedFactsSeenAt('b1', 'u1'), t0);
    expect(case_.pinnedFactsSeenAt('b1', 'u2'), t1);
    expect(case_.pinnedFactsSeenAt('b2', 'u1'), t1);
  });

  test('first baseline is sticky', () {
    final case_ = buildTestBeaconViewCase();
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'a', createdAt: t0)],
    );
    case_.baselinePinnedFactsIfNeeded(
      beaconId: 'b1',
      userId: 'u1',
      facts: [_fact(id: 'b', createdAt: t1)],
    );
    expect(case_.pinnedFactsSeenAt('b1', 'u1'), t0);
  });

  test('mark seen uses max fact timestamp, not wall clock', () {
    final case_ = buildTestBeaconViewCase();
    final before = DateTime.now().toUtc();
    case_.markPinnedFactsSeen(
      beaconId: 'b1',
      userId: 'u1',
      facts: [
        _fact(id: 'a', createdAt: t0),
        _fact(id: 'b', createdAt: t0, updatedAt: t1),
      ],
    );
    final seen = case_.pinnedFactsSeenAt('b1', 'u1');
    expect(seen, t1);
    expect(seen!.isBefore(before) || seen.isAtSameMomentAs(t1), isTrue);
  });

  test('empty facts mark epoch', () {
    final case_ = buildTestBeaconViewCase();
    case_.markPinnedFactsSeen(
      beaconId: 'b1',
      userId: 'u1',
      facts: const [],
    );
    expect(case_.pinnedFactsSeenAt('b1', 'u1'), epoch);
  });
}
