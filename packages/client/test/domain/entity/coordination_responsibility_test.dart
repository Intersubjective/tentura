import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';

void main() {
  group('CoordinationResponsibility', () {
    test('hasAny is false when all open counts are zero', () {
      const r = CoordinationResponsibility(beaconId: 'b1');
      expect(r.hasAny, isFalse);
      expect(r.totalNew, 0);
      expect(r.orderedEntries, isEmpty);
    });

    test('orderedEntries follow ask → promise → blocker → review', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 2,
        promiseOpen: 1,
        blockerOpen: 3,
        reviewOpen: 1,
        askNew: 1,
        reviewNew: 2,
      );
      expect(
        r.orderedEntries.map((e) => e.kind).toList(),
        [
          CoordinationItemKind.ask,
          CoordinationItemKind.promise,
          CoordinationItemKind.blocker,
          CoordinationItemKind.resolution,
        ],
      );
      expect(r.orderedEntries.first.newCount, 1);
      expect(r.totalNew, 3);
    });

    test('withNewCountsCleared zeros new counts only', () {
      const r = CoordinationResponsibility(
        beaconId: 'b1',
        askOpen: 1,
        askNew: 2,
        promiseNew: 1,
      );
      final cleared = r.withNewCountsCleared();
      expect(cleared.askOpen, 1);
      expect(cleared.totalNew, 0);
    });
  });
}
