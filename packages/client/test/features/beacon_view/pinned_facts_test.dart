import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';

BeaconFactCard _fact({
  required String id,
  required DateTime createdAt,
  DateTime? updatedAt,
  String pinnedBy = 'other',
  int status = BeaconFactCardStatusBits.active,
}) =>
    BeaconFactCard(
      id: id,
      beaconId: 'b1',
      factText: id,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: pinnedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: status,
    );

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final t2 = DateTime.utc(2026, 1, 3);

  test('activePinnedFacts drops removed and sorts newest first', () {
    final facts = [
      _fact(id: 'old', createdAt: t0),
      _fact(id: 'gone', createdAt: t2, status: BeaconFactCardStatusBits.removed),
      _fact(id: 'new', createdAt: t1),
    ];
    expect(activePinnedFacts(facts).map((f) => f.id), ['new', 'old']);
  });

  test('null seenAt yields zero new (baseline not applied)', () {
    expect(
      pinnedFactsNewCount(
        facts: [_fact(id: 'a', createdAt: t1, pinnedBy: 'other')],
        seenAt: null,
        viewerUserId: 'me',
      ),
      0,
    );
  });

  test('own pin is never new', () {
    expect(
      pinnedFactsNewCount(
        facts: [_fact(id: 'a', createdAt: t2, pinnedBy: 'me')],
        seenAt: t0,
        viewerUserId: 'me',
      ),
      0,
    );
  });

  test('facts after watermark count as new', () {
    expect(
      pinnedFactsNewCount(
        facts: [
          _fact(id: 'old', createdAt: t0, pinnedBy: 'other'),
          _fact(id: 'new', createdAt: t2, pinnedBy: 'other'),
        ],
        seenAt: t1,
        viewerUserId: 'me',
      ),
      1,
    );
  });

  test('max timestamp prefers updatedAt', () {
    expect(
      activePinnedFactsMaxTimestamp([
        _fact(id: 'a', createdAt: t0, updatedAt: t2),
        _fact(id: 'b', createdAt: t1),
      ]),
      t2,
    );
  });

  test('removed facts are not new', () {
    expect(
      pinnedFactsNewCount(
        facts: [
          _fact(
            id: 'gone',
            createdAt: t2,
            pinnedBy: 'other',
            status: BeaconFactCardStatusBits.removed,
          ),
        ],
        seenAt: t0,
        viewerUserId: 'me',
      ),
      0,
    );
  });
}
