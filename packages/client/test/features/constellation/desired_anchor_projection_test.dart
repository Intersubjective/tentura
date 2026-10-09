import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/placement_outbox.dart';
import 'package:tentura/features/constellation/domain/placement_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_clock_port.dart';

const _oldPosition = ConstellationAnchorPosition(
  xUnits: 1,
  yUnits: 2,
  coordinateSpaceVersion: 1,
);
const _newPosition = ConstellationAnchorPosition(
  xUnits: 3,
  yUnits: 4,
  coordinateSpaceVersion: 1,
);
const _latestPosition = ConstellationAnchorPosition(
  xUnits: -3,
  yUnits: -4,
  coordinateSpaceVersion: 1,
);
final _person = ConstellationAnchorTarget.person('shared-id');
final _beacon = ConstellationAnchorTarget.beacon('shared-id');
final _untouched = ConstellationAnchorTarget.person('untouched');

ConstellationAnchor _anchor(ConstellationAnchorTarget target) =>
    ConstellationAnchor(
      target: target,
      position: _oldPosition,
      revision: ConstellationAnchorRevision(BigInt.from(7)),
      placedAt: DateTime.utc(2026, 10, 8),
    );

ConstellationAnchorProjection _confirmed(List<ConstellationAnchor> anchors) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision(BigInt.from(9)),
      anchors: anchors,
      pinnedPeers: const [ConstellationPerson(id: 'shared-id')],
      pinnedRequests: const [
        ConstellationRequest(
          id: 'shared-id',
          authorId: 'author',
          title: 'Pinned request',
          status: 0,
        ),
      ],
      supportPeers: const [ConstellationPerson(id: 'support')],
      supportEdges: const [
        ConstellationTrustEdgeEntity(src: 'support', dst: 'shared-id', tier: 1),
      ],
      serverFilteredBeaconIds: const ['filtered'],
      serverFilteredBeaconCount: 1,
    );

PlacementOp _upsert(
  ConstellationAnchorTarget target, {
  String clientOpId = 'upsert',
  ConstellationAnchorPosition position = _newPosition,
}) => PlacementOp.upsert(
  clientOpId: clientOpId,
  clusterId: 'cluster',
  target: target,
  position: position,
);

PlacementOp _delete(ConstellationAnchorTarget target) => PlacementOp.delete(
  clientOpId: 'delete',
  clusterId: 'cluster',
  target: target,
);

PlacementOutboxState _outbox(
  Map<ConstellationAnchorTarget, PlacementTargetState> targets,
) => PlacementOutboxState(
  targets: targets,
  hasUserPlacements: true,
  generation: 1,
);

Map<ConstellationAnchorTarget, ConstellationAnchorPosition> _positions(
  ConstellationAnchorProjection projection,
) => {for (final anchor in projection.anchors) anchor.target: anchor.position};

void main() {
  late FakeClockPort clock;

  setUp(() {
    clock = FakeClockPort(DateTime.utc(2026, 10, 8, 12));
  });

  group('Desired anchor projection', () {
    test('empty outbox preserves the confirmed projection', () {
      final confirmed = _confirmed([_anchor(_person)]);

      final result = desiredAnchorProjection(
        confirmed,
        _outbox({}),
        now: clock.now(),
      );

      expect(result.projection, confirmed);
      expect(result.unsaved, isEmpty);
    });

    test('upserts replace existing anchors and add unanchored targets', () {
      final confirmed = _confirmed([_anchor(_person), _anchor(_untouched)]);
      final outbox = _outbox({
        _person: PlacementTargetState(
          latestPending: PlacementSlot(
            op: _upsert(_person),
            status: PlacementSlotStatus.queued,
          ),
        ),
        _beacon: PlacementTargetState(
          latestPending: PlacementSlot(
            op: _upsert(_beacon),
            status: PlacementSlotStatus.queued,
          ),
        ),
      });

      final result = desiredAnchorProjection(
        confirmed,
        outbox,
        now: clock.now(),
      );

      expect(_positions(result.projection), {
        _person: _newPosition,
        _beacon: _newPosition,
        _untouched: _oldPosition,
      });
      expect(result.projection.anchors, hasLength(3));
      expect(result.unsaved, isEmpty);
      expect(_positions(confirmed), {
        _person: _oldPosition,
        _untouched: _oldPosition,
      });
      expect(
        outbox.targets[_person]!.latestPending!.status,
        PlacementSlotStatus.queued,
      );
    });

    test('deletes remove only their exact target kind and id', () {
      final confirmed = _confirmed([
        _anchor(_person),
        _anchor(_beacon),
        _anchor(_untouched),
      ]);

      final result = desiredAnchorProjection(
        confirmed,
        _outbox({
          _person: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _delete(_person),
              status: PlacementSlotStatus.queued,
            ),
          ),
        }),
        now: clock.now(),
      );

      expect(_positions(result.projection), {
        _beacon: _oldPosition,
        _untouched: _oldPosition,
      });
      expect(confirmed.anchors, hasLength(3));
    });

    test('a delete also drops the pinned entity of its exact target kind', () {
      final confirmed = _confirmed([_anchor(_person), _anchor(_beacon)]);

      ConstellationAnchorProjection desiredAfter(
        ConstellationAnchorTarget target,
      ) => desiredAnchorProjection(
        confirmed,
        _outbox({
          target: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _delete(target),
              status: PlacementSlotStatus.queued,
            ),
          ),
        }),
        now: clock.now(),
      ).projection;

      final personUnpinned = desiredAfter(_person);
      expect(personUnpinned.pinnedPeers, isEmpty);
      expect(personUnpinned.pinnedRequests, confirmed.pinnedRequests);

      final beaconUnpinned = desiredAfter(_beacon);
      expect(beaconUnpinned.pinnedRequests, isEmpty);
      expect(beaconUnpinned.pinnedPeers, confirmed.pinnedPeers);
    });

    test('upserts and deletes are overlaid together across targets', () {
      final result = desiredAnchorProjection(
        _confirmed([_anchor(_person), _anchor(_beacon)]),
        _outbox({
          _person: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _upsert(_person),
              status: PlacementSlotStatus.queued,
            ),
          ),
          _beacon: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _delete(_beacon),
              status: PlacementSlotStatus.queued,
            ),
          ),
        }),
        now: clock.now(),
      );

      expect(_positions(result.projection), {_person: _newPosition});
    });

    test('deleting an unanchored target leaves other anchors intact', () {
      final result = desiredAnchorProjection(
        _confirmed([_anchor(_untouched)]),
        _outbox({
          _person: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _delete(_person),
              status: PlacementSlotStatus.queued,
            ),
          ),
        }),
        now: clock.now(),
      );

      expect(_positions(result.projection), {_untouched: _oldPosition});
    });

    for (final status in PlacementSlotStatus.values) {
      test(
        'unresolved ${status.name} upsert remains at its desired position',
        () {
          final slot = PlacementSlot(
            op: _upsert(_person),
            status: status,
            inFlightSince: status == PlacementSlotStatus.queued
                ? null
                : clock.now(),
          );
          final result = desiredAnchorProjection(
            _confirmed([_anchor(_person)]),
            _outbox({
              _person:
                  status == PlacementSlotStatus.queued ||
                      status == PlacementSlotStatus.rejected
                  ? PlacementTargetState(latestPending: slot)
                  : PlacementTargetState(inFlight: slot),
            }),
            now: clock.now(),
          );

          expect(_positions(result.projection), {_person: _newPosition});
        },
      );
    }

    for (final status in [
      PlacementSlotStatus.inFlight,
      PlacementSlotStatus.commitUnknown,
    ]) {
      test(
        '${status.name} delete removes the confirmed anchor without a successor',
        () {
          final confirmed = _confirmed([
            _anchor(_person),
            _anchor(_untouched),
          ]);
          final outbox = _outbox({
            _person: PlacementTargetState(
              inFlight: PlacementSlot(
                op: _delete(_person),
                status: status,
                inFlightSince: clock.now(),
              ),
            ),
          });

          final result = desiredAnchorProjection(
            confirmed,
            outbox,
            now: clock.now(),
          );

          expect(outbox.targets[_person]!.latestPending, isNull);
          expect(_positions(result.projection), {_untouched: _oldPosition});
          expect(_positions(confirmed), {
            _person: _oldPosition,
            _untouched: _oldPosition,
          });
        },
      );
    }

    for (final status in [
      PlacementSlotStatus.queued,
      PlacementSlotStatus.rejected,
    ]) {
      for (final delete in [false, true]) {
        final operation = delete ? 'delete' : 'upsert';
        test(
          'removing a ${status.name} $operation restores the confirmed anchor',
          () {
            final confirmed = _confirmed([
              _anchor(_person),
              _anchor(_untouched),
            ]);
            final outbox = _outbox({
              _person: PlacementTargetState(
                latestPending: PlacementSlot(
                  op: delete ? _delete(_person) : _upsert(_person),
                  status: status,
                ),
              ),
            });
            final beforeRemoval = desiredAnchorProjection(
              confirmed,
              outbox,
              now: clock.now(),
            );

            expect(_positions(beforeRemoval.projection), {
              if (!delete) _person: _newPosition,
              _untouched: _oldPosition,
            });

            final afterRemoval = desiredAnchorProjection(
              confirmed,
              outbox.copyWith(targets: {}),
              now: clock.now(),
            );

            expect(afterRemoval.projection, confirmed);
            expect(_positions(afterRemoval.projection), {
              _person: _oldPosition,
              _untouched: _oldPosition,
            });
            expect(afterRemoval.unsaved, isEmpty);
          },
        );
      }
    }

    test('latest pending upsert supersedes an in-flight upsert', () {
      final result = desiredAnchorProjection(
        _confirmed([_anchor(_person)]),
        _outbox({
          _person: PlacementTargetState(
            inFlight: PlacementSlot(
              op: _upsert(_person),
              status: PlacementSlotStatus.inFlight,
              inFlightSince: clock.now(),
            ),
            latestPending: PlacementSlot(
              op: _upsert(
                _person,
                clientOpId: 'successor',
                position: _latestPosition,
              ),
              status: PlacementSlotStatus.queued,
            ),
          ),
        }),
        now: clock.now(),
      );

      expect(_positions(result.projection), {_person: _latestPosition});
      expect(result.projection.anchors, hasLength(1));
    });

    for (final pendingDelete in [false, true]) {
      test(
        pendingDelete
            ? 'latest pending delete supersedes an in-flight upsert'
            : 'latest pending upsert supersedes an in-flight delete',
        () {
          final result = desiredAnchorProjection(
            _confirmed([_anchor(_person)]),
            _outbox({
              _person: PlacementTargetState(
                inFlight: PlacementSlot(
                  op: pendingDelete ? _upsert(_person) : _delete(_person),
                  status: PlacementSlotStatus.inFlight,
                  inFlightSince: clock.now(),
                ),
                latestPending: PlacementSlot(
                  op: pendingDelete ? _delete(_person) : _upsert(_person),
                  status: PlacementSlotStatus.queued,
                ),
              ),
            }),
            now: clock.now(),
          );

          expect(
            _positions(result.projection),
            pendingDelete
                ? <ConstellationAnchorTarget, ConstellationAnchorPosition>{}
                : {_person: _newPosition},
          );
        },
      );
    }

    test(
      'overlay preserves server revision and authorized projection data',
      () {
        final confirmed = _confirmed([_anchor(_person)]);
        final result = desiredAnchorProjection(
          confirmed,
          _outbox({
            _person: PlacementTargetState(
              latestPending: PlacementSlot(
                op: _upsert(_person),
                status: PlacementSlotStatus.queued,
              ),
            ),
          }),
          now: clock.now(),
        );
        final projection = result.projection;

        expect(projection.revision, confirmed.revision);
        expect(projection.pinnedPeers, confirmed.pinnedPeers);
        expect(projection.pinnedRequests, confirmed.pinnedRequests);
        expect(projection.supportPeers, confirmed.supportPeers);
        expect(projection.supportEdges, confirmed.supportEdges);
        expect(
          projection.serverFilteredBeaconIds,
          confirmed.serverFilteredBeaconIds,
        );
        expect(
          projection.serverFilteredBeaconCount,
          confirmed.serverFilteredBeaconCount,
        );
      },
    );
  });

  group('Unsaved placement targets', () {
    for (final delete in [false, true]) {
      test(
        delete
            ? 'rejected delete remains removed and marks its target unsaved'
            : 'rejected upsert stays at its desired position and marks its target unsaved',
        () {
          final result = desiredAnchorProjection(
            _confirmed([_anchor(_person)]),
            _outbox({
              _person: PlacementTargetState(
                latestPending: PlacementSlot(
                  op: delete ? _delete(_person) : _upsert(_person),
                  status: PlacementSlotStatus.rejected,
                  reasonCode: 'target_unavailable',
                ),
              ),
            }),
            now: clock.now(),
          );

          expect(result.unsaved, {_person});
          expect(
            _positions(result.projection),
            delete
                ? <ConstellationAnchorTarget, ConstellationAnchorPosition>{}
                : {_person: _newPosition},
          );
        },
      );
    }

    for (final attempts in [0, 1, 2, 3, 4]) {
      test(
        attempts >= 3
            ? 'exhausted commit uncertainty exposes an unsaved cue (attempts: $attempts)'
            : 'retryable commit uncertainty has no unsaved cue (attempts: $attempts)',
        () {
          final result = desiredAnchorProjection(
            _confirmed([_anchor(_person)]),
            _outbox({
              _person: PlacementTargetState(
                inFlight: PlacementSlot(
                  op: _upsert(_person),
                  status: PlacementSlotStatus.commitUnknown,
                  attempts: attempts,
                  inFlightSince: clock.now().subtract(
                    const Duration(minutes: 1),
                  ),
                ),
              ),
            }),
            now: clock.now(),
          );

          expect(result.unsaved, attempts >= 3 ? {_person} : isEmpty);
          expect(_positions(result.projection), {_person: _newPosition});
        },
      );
    }

    for (final delete in [false, true]) {
      final operation = delete ? 'delete' : 'upsert';
      test('in-flight $operation uses the saving cue delay threshold', () {
        final confirmed = _confirmed([_anchor(_person)]);
        final outbox = _outbox({
          _person: PlacementTargetState(
            inFlight: PlacementSlot(
              op: delete ? _delete(_person) : _upsert(_person),
              status: PlacementSlotStatus.inFlight,
              inFlightSince: clock.now(),
            ),
          ),
        });

        expect(
          desiredAnchorProjection(confirmed, outbox, now: clock.now()).unsaved,
          isEmpty,
        );
        clock.advance(const Duration(milliseconds: 999));
        expect(
          desiredAnchorProjection(confirmed, outbox, now: clock.now()).unsaved,
          isEmpty,
        );
        clock.advance(const Duration(milliseconds: 1));
        expect(
          desiredAnchorProjection(confirmed, outbox, now: clock.now()).unsaved,
          isEmpty,
        );
        clock.advance(const Duration(microseconds: 1));
        final result = desiredAnchorProjection(
          confirmed,
          outbox,
          now: clock.now(),
        );
        expect(result.unsaved, {_person});
        expect(_positions(result.projection), {
          if (!delete) _person: _newPosition,
        });
      });

      test(
        'in-flight $operation without a start time has no elapsed-time cue',
        () {
          final confirmed = _confirmed([_anchor(_person)]);
          final slot = PlacementSlot(
            op: delete ? _delete(_person) : _upsert(_person),
            status: PlacementSlotStatus.inFlight,
          );
          final outbox = _outbox({
            _person: PlacementTargetState(inFlight: slot),
          });

          expect(slot.inFlightSince, isNull);
          expect(
            desiredAnchorProjection(
              confirmed,
              outbox,
              now: clock.now(),
            ).unsaved,
            isEmpty,
          );
          clock.advance(const Duration(minutes: 1));

          final result = desiredAnchorProjection(
            confirmed,
            outbox,
            now: clock.now(),
          );

          expect(result.unsaved, isEmpty);
          expect(_positions(result.projection), {
            if (!delete) _person: _newPosition,
          });
        },
      );
    }

    test('queued intent is not marked unsaved merely by elapsed time', () {
      final outbox = _outbox({
        _person: PlacementTargetState(
          latestPending: PlacementSlot(
            op: _upsert(_person),
            status: PlacementSlotStatus.queued,
          ),
        ),
      });
      clock.advance(const Duration(minutes: 1));

      final result = desiredAnchorProjection(
        _confirmed([]),
        outbox,
        now: clock.now(),
      );

      expect(result.unsaved, isEmpty);
      expect(_positions(result.projection), {_person: _newPosition});
    });

    test(
      'unsaved targets are collected independently without losing precedence',
      () {
        final outbox = _outbox({
          _person: PlacementTargetState(
            latestPending: PlacementSlot(
              op: _upsert(_person),
              status: PlacementSlotStatus.rejected,
            ),
          ),
          _beacon: PlacementTargetState(
            inFlight: PlacementSlot(
              op: _delete(_beacon),
              status: PlacementSlotStatus.commitUnknown,
              attempts: 3,
            ),
            latestPending: PlacementSlot(
              op: _upsert(_beacon, position: _latestPosition),
              status: PlacementSlotStatus.queued,
            ),
          ),
          _untouched: PlacementTargetState(
            inFlight: PlacementSlot(
              op: _upsert(_untouched),
              status: PlacementSlotStatus.inFlight,
              inFlightSince: clock.now(),
            ),
          ),
        });
        clock.advance(const Duration(seconds: 2));

        final result = desiredAnchorProjection(
          _confirmed([]),
          outbox,
          now: clock.now(),
        );

        expect(result.unsaved, {_person, _beacon, _untouched});
        expect(_positions(result.projection), {
          _person: _newPosition,
          _beacon: _latestPosition,
          _untouched: _newPosition,
        });
      },
    );
  });
}
