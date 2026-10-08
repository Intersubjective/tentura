import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/placement_outbox.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

const _position = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: -2,
  coordinateSpaceVersion: 1,
);
final _target = ConstellationAnchorTarget.person('peer');

PlacementOp _upsert() => PlacementOp.upsert(
  clientOpId: 'upsert',
  clusterId: 'cluster',
  target: _target,
  position: _position,
);

void main() {
  group('Placement operation values', () {
    test(
      'identical upserts compare by value and preserve operation identity',
      () {
        final first = _upsert();
        final second = _upsert();

        expect(first, second);
        expect(first.hashCode, second.hashCode);
        expect(first.clientOpId, 'upsert');
        expect(first.clusterId, 'cluster');
        expect(first.target, _target);
        expect(first, isA<PlacementUpsert>());
        expect((first as PlacementUpsert).position, _position);
        expect(first.ifRevision, isNull);
      },
    );

    test('delete retains the optional compensation revision as a value', () {
      final revision = ConstellationAnchorRevision(BigInt.from(11));
      final op = PlacementOp.delete(
        clientOpId: 'delete',
        clusterId: 'compensation',
        target: _target,
        ifRevision: revision,
      );

      expect(op, isA<PlacementDelete>());
      expect(op.clientOpId, 'delete');
      expect(op.clusterId, 'compensation');
      expect(op.target, _target);
      expect(op.ifRevision, revision);
      expect(
        op,
        PlacementOp.delete(
          clientOpId: 'delete',
          clusterId: 'compensation',
          target: _target,
          ifRevision: revision,
        ),
      );
      expect(op, isNot(_upsert()));
    });
  });

  group('Placement outbox values', () {
    test(
      'slot replacement retains the original operation and discard baseline',
      () {
        final baseline = ConstellationAnchor(
          target: _target,
          position: _position,
          revision: ConstellationAnchorRevision.zero,
          placedAt: DateTime.utc(2026, 10, 8),
        );
        final slot = PlacementSlot(
          op: _upsert(),
          status: PlacementSlotStatus.queued,
          preOpConfirmed: baseline,
        );
        final rejected = slot.copyWith(
          status: PlacementSlotStatus.rejected,
          attempts: 3,
          reasonCode: 'conflict',
        );

        expect(slot.attempts, 0);
        expect(slot.reasonCode, isNull);
        expect(slot.status, PlacementSlotStatus.queued);
        expect(rejected.op, slot.op);
        expect(rejected.preOpConfirmed, baseline);
        expect(rejected.attempts, 3);
        expect(rejected.reasonCode, 'conflict');
        expect(rejected.status, PlacementSlotStatus.rejected);
      },
    );

    test('pending replacement keeps the independent in-flight slot intact', () {
      final inFlight = PlacementSlot(
        op: _upsert(),
        status: PlacementSlotStatus.inFlight,
      );
      final original = PlacementTargetState(inFlight: inFlight);
      final pending = PlacementSlot(
        op: PlacementOp.delete(
          clientOpId: 'successor',
          clusterId: 'next-cluster',
          target: _target,
        ),
        status: PlacementSlotStatus.queued,
      );
      final replaced = original.copyWith(latestPending: pending);

      expect(original.latestPending, isNull);
      expect(replaced.inFlight, inFlight);
      expect(replaced.latestPending, pending);
      expect(replaced.copyWith(latestPending: null), original);
    });

    test(
      'outbox compares target maps by value and preserves the original on replacement',
      () {
        final targetState = PlacementTargetState(
          latestPending: PlacementSlot(
            op: _upsert(),
            status: PlacementSlotStatus.queued,
          ),
        );
        final original = PlacementOutboxState(
          targets: {_target: targetState},
          hasUserPlacements: true,
          generation: 2,
        );
        final equivalent = PlacementOutboxState(
          targets: {_target: targetState},
          hasUserPlacements: true,
          generation: 2,
        );
        final cleared = original.copyWith(targets: {}, generation: 3);

        expect(original, equivalent);
        expect(original.hashCode, equivalent.hashCode);
        expect(original.targets, {_target: targetState});
        expect(original.generation, 2);
        expect(cleared.targets, isEmpty);
        expect(cleared.generation, 3);
        expect(cleared.hasUserPlacements, isTrue);
      },
    );
  });
}
