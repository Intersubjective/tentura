import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/placement_outbox.dart';
import 'package:tentura/features/constellation/domain/placement_overlay.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

const _ego = 'ego';
const _caseCount = 200;
const _personSize = (width: 40.0, height: 40.0);
const _requestSize = (width: 36.0, height: 36.0);

/// A generated field: ego-adjacent people and the Requests they author.
class _Field {
  _Field({required this.people, required this.requestsByAuthor});

  final Set<String> people;
  final Map<String, List<String>> requestsByAuthor;

  _Field copy() => _Field(
    people: {...people},
    requestsByAuthor: {
      for (final e in requestsByAuthor.entries) e.key: [...e.value],
    },
  );

  Set<String> get requests => {
    for (final ids in requestsByAuthor.values) ...ids,
  };

  String? authorOf(String requestId) {
    for (final e in requestsByAuthor.entries) {
      if (e.value.contains(requestId)) {
        return e.key;
      }
    }
    return null;
  }
}

ConstellationLayout _place(
  _Field field, {
  ConstellationLayoutPriorHints? previous,
  Map<String, ConstellationAnchorPosition> anchors = const {},
  Map<String, ConstellationSize> sizeOverrides = const {},
}) {
  final paths = resolveConstellationPaths(
    egoId: _ego,
    visiblePeerIds: field.people,
    holderIds: field.people,
    edges: [
      for (final id in field.people) (src: _ego, dst: id, tier: 1),
    ],
  );
  return computeConstellationPlacedLayout(
    input: (
      egoId: _ego,
      paths: paths,
      automaticKeptPeerIds: field.people,
      pinnedPersonIds: {
        for (final id in anchors.keys)
          if (field.people.contains(id)) id,
      },
      pinnedRequestIds: {
        for (final id in anchors.keys)
          if (field.requests.contains(id)) id,
      },
      supportPersonIds: const {},
      anchorByNodeId: anchors,
      priorHints: previous,
      nodeSizes: {
        for (final id in field.people) id: _personSize,
        for (final id in field.requests) id: _requestSize,
        ...sizeOverrides,
      },
      satelliteRequestIdsByAuthor: field.requestsByAuthor,
      requestAuthorById: {
        for (final e in field.requestsByAuthor.entries)
          for (final id in e.value) id: e.key,
      },
      egoOwnRequestIds: const {},
      spacing: 16,
      maxHops: 3,
      viewportClass: ConstellationViewportClass.expanded,
      footprints: const {},
    ),
  );
}

ConstellationLayoutPriorHints _asPrevious(ConstellationLayout layout) => (
  positions: layout.positions,
  ring: layout.ring,
  viewportClass: ConstellationViewportClass.expanded,
);

_Field _randomField(math.Random rnd) {
  final people = <String>{
    for (var i = 0; i < 5 + rnd.nextInt(9); i++)
      'person-m${i.toString().padLeft(2, '0')}',
  };
  final requestsByAuthor = <String, List<String>>{};
  var requestSeq = 0;
  for (final id in people) {
    final count = rnd.nextInt(3);
    if (count > 0) {
      requestsByAuthor[id] = [
        for (var i = 0; i < count; i++)
          'req-m${(requestSeq++).toString().padLeft(2, '0')}',
      ];
    }
  }
  return _Field(people: people, requestsByAuthor: requestsByAuthor);
}

/// The people whose satellite fan or seat a diff must not disturb in order to
/// leave [touched] untouched: each touched person, and the author of each
/// touched Request.
Set<String> _protectedAuthors(Set<String> touched, _Field field) => {
  for (final id in touched)
    if (field.people.contains(id)) id else field.authorOf(id) ?? id,
};

/// Applies a random diff that does not touch any of [touched]: it adds people
/// and Requests (ids deliberately sorting both before and after the existing
/// ones) and removes other nodes, but never removes or adds anything for a
/// touched node's author (so the author seat and the sibling fan stay as they
/// were) and never changes the touched nodes themselves.
_Field _diffNotTouching(Set<String> touched, _Field before, math.Random rnd) {
  final after = before.copy();
  final protectedAuthors = _protectedAuthors(touched, before);

  final removable = <String>[
    for (final id in before.people)
      if (!touched.contains(id) && !protectedAuthors.contains(id)) id,
  ]..shuffle(rnd);
  for (final id in removable.take(rnd.nextInt(3))) {
    after.people.remove(id);
    after.requestsByAuthor.remove(id);
  }
  for (final id in [
    for (final id in before.requests)
      if (!touched.contains(id) &&
          !protectedAuthors.contains(before.authorOf(id)))
        id,
  ]) {
    if (rnd.nextInt(5) == 0) {
      after.requestsByAuthor[after.authorOf(id)]?.remove(id);
    }
  }

  final prefixes = ['person-a', 'person-m5', 'person-z'];
  for (var i = 0; i < 1 + rnd.nextInt(4); i++) {
    final id = '${prefixes[rnd.nextInt(prefixes.length)]}-new$i';
    after.people.add(id);
    if (rnd.nextBool()) {
      after.requestsByAuthor[id] = ['req-${rnd.nextBool() ? 'a' : 'z'}-new$i'];
    }
  }
  final authors = [
    for (final id in after.people)
      if (!protectedAuthors.contains(id)) id,
  ];
  for (var i = 0; i < rnd.nextInt(3); i++) {
    final author = authors[rnd.nextInt(authors.length)];
    (after.requestsByAuthor[author] ??= []).add('req-a-extra$i');
  }
  return after..requestsByAuthor.removeWhere((_, ids) => ids.isEmpty);
}

/// Applies a diff concentrated around [x]'s ring neighbourhood: the people
/// adjacent to [x]'s seat (or to its author's seat) are removed or given extra
/// Requests, and new people are added whose ids sort right beside [x]'s seat.
/// [x] and its author (with the whole sibling fan) are left alone.
_Field _diffAroundNeighbours(String x, _Field before, math.Random rnd) {
  final after = before.copy();
  final seat = before.people.contains(x) ? x : before.authorOf(x)!;
  final sorted = before.people.toList()..sort();
  final at = sorted.indexOf(seat);
  final neighbours = [
    if (at > 0) sorted[at - 1],
    if (at < sorted.length - 1) sorted[at + 1],
  ];

  for (final id in neighbours) {
    if (rnd.nextBool()) {
      after.people.remove(id);
      after.requestsByAuthor.remove(id);
    } else {
      (after.requestsByAuthor[id] ??= []).add('req-near-$id');
    }
  }
  var added = 0;
  for (final id in [
    if (at > 0) sorted[at - 1],
    seat,
  ]) {
    for (var i = 0; i <= rnd.nextInt(2); i++) {
      final person = '$id-near$i';
      after.people.add(person);
      after.requestsByAuthor[person] = ['req-near-new${added++}'];
    }
  }
  return after;
}

/// `null` when [id] sits at the same place in both layouts, else a message.
String? _movedOrMissing(
  String id,
  ConstellationLayout was,
  ConstellationLayout now,
) {
  final before = was.positions[id];
  final after = now.positions[id];
  if (before == null) {
    return '$id has no baseline position (test setup error)';
  }
  if (after == null) {
    return '$id lost its position';
  }
  return before == after ? null : '$id moved $before -> $after';
}

/// What the contract "new nodes go into free space" demands of [next]: every
/// node present in [after] but not in [before] has a position, and its body
/// overlaps no other node's body. This is also what makes the immobility
/// checks fair: a newcomer that lands in free space can never be the "new
/// overlap" that would legitimately displace an existing free node.
List<String> _newcomerProblems(
  _Field before,
  _Field after,
  ConstellationLayout next,
) {
  const egoSize = (width: 64.0, height: 64.0);
  ConstellationSize sizeOf(String id) => id == _ego
      ? egoSize
      : after.people.contains(id)
      ? _personSize
      : _requestSize;
  final all = {_ego, ...after.people, ...after.requests};
  final newcomers = all.difference({
    _ego,
    ...before.people,
    ...before.requests,
  });
  final problems = <String>[];
  for (final id in newcomers) {
    final at = next.positions[id];
    if (at == null) {
      problems.add('new node $id was not placed');
      continue;
    }
    final body = constellationRenderedBounds(centre: at, size: sizeOf(id));
    for (final other in all) {
      final otherAt = next.positions[other];
      if (other == id || otherAt == null) {
        continue;
      }
      final otherBody = constellationRenderedBounds(
        centre: otherAt,
        size: sizeOf(other),
      );
      if (_rectsOverlap(body, otherBody)) {
        problems.add('new node $id overlaps $other');
      }
    }
  }
  return problems;
}

bool _rectsOverlap(ConstellationBounds a, ConstellationBounds b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

void main() {
  group('Constellation layout positional stability', () {
    test(
      'a node keeps its position across 200 seeded diffs that do not touch it',
      () {
        final violations = <String>[];
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(seed);
          final before = _randomField(rnd);
          final baseline = _place(before);

          final candidates = [...before.people, ...before.requests]..sort();
          final x = candidates[rnd.nextInt(candidates.length)];
          final after = _diffNotTouching({x}, before, rnd);
          expect(
            {...after.people, ...after.requests},
            contains(x),
            reason: 'seed $seed',
          );

          final next = _place(after, previous: _asPrevious(baseline));

          final problem = _movedOrMissing(x, baseline, next);
          if (problem != null) {
            violations.add('seed $seed: $problem');
          }
          for (final p in _newcomerProblems(before, after, next)) {
            violations.add('seed $seed: $p');
          }
        }
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test(
      'a node keeps its position when its ring neighbours are removed, given '
      'extra Requests, or crowded by new people sorting right beside it',
      () {
        final violations = <String>[];
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(500 + seed);
          final before = _randomField(rnd);
          final baseline = _place(before);

          final candidates = [...before.people, ...before.requests]..sort();
          final x = candidates[rnd.nextInt(candidates.length)];
          final after = _diffAroundNeighbours(x, before, rnd);
          final next = _place(after, previous: _asPrevious(baseline));

          final problem = _movedOrMissing(x, baseline, next);
          if (problem != null) {
            violations.add('seed $seed: $problem');
          }
          for (final p in _newcomerProblems(before, after, next)) {
            violations.add('seed $seed: $p');
          }
        }
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test(
      'every node whose inputs are unchanged keeps its position when only '
      'other nodes are added',
      () {
        final violations = <String>[];
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(1000 + seed);
          final before = _randomField(rnd);
          final baseline = _place(before);

          final after = before.copy();
          for (var i = 0; i < 1 + rnd.nextInt(4); i++) {
            after.people.add('person-a-added$i');
          }
          final next = _place(after, previous: _asPrevious(baseline));

          for (final id in [...before.people, ...before.requests]) {
            final problem = _movedOrMissing(id, baseline, next);
            if (problem != null) {
              violations.add('seed $seed: $problem');
            }
          }
          for (final p in _newcomerProblems(before, after, next)) {
            violations.add('seed $seed: $p');
          }
        }
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test(
      'a Request whose body grows displaces only nodes it now overlaps; all '
      'other nodes keep their position',
      () {
        const grown = (width: 300.0, height: 300.0);
        const spacing = 16.0;
        final violations = <String>[];
        var checked = 0;
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(3000 + seed);
          final field = _randomField(rnd);
          final requests = field.requests.toList()..sort();
          if (requests.isEmpty) {
            continue;
          }
          final baseline = _place(field);
          final changed = requests[rnd.nextInt(requests.length)];
          final next = _place(
            field,
            previous: _asPrevious(baseline),
            sizeOverrides: {changed: grown},
          );

          final changedOld = baseline.positions[changed]!;
          final growth = (
            left: changedOld.x - grown.width / 2 - spacing,
            top: changedOld.y - grown.height / 2 - spacing,
            right: changedOld.x + grown.width / 2 + spacing,
            bottom: changedOld.y + grown.height / 2 + spacing,
          );
          for (final id in [...field.people, ...field.requests]) {
            if (id == changed) {
              continue;
            }
            final old = baseline.positions[id]!;
            final size = field.people.contains(id) ? _personSize : _requestSize;
            final body = constellationRenderedBounds(centre: old, size: size);
            if (_rectsOverlap(growth, body)) {
              continue;
            }
            checked++;
            final problem = _movedOrMissing(id, baseline, next);
            if (problem != null) {
              violations.add('seed $seed (grown $changed): $problem');
            }
          }
        }
        expect(
          checked,
          greaterThan(_caseCount),
          reason: 'too few nodes checked',
        );
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test(
      'user-placed nodes stay on their anchor and free nodes still keep their '
      'position when other nodes change',
      () {
        final violations = <String>[];
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(4000 + seed);
          final before = _randomField(rnd);
          final people = before.people.toList()..sort();
          final requests = before.requests.toList()..sort();
          final pinnedPerson = people[rnd.nextInt(people.length)];
          final pinnedRequest = requests.isEmpty
              ? null
              : requests[rnd.nextInt(requests.length)];
          final anchors = {
            pinnedPerson: const ConstellationAnchorPosition(
              xUnits: 2,
              yUnits: -1.5,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
            ?pinnedRequest: const ConstellationAnchorPosition(
              xUnits: -1.5,
              yUnits: 2,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
          };
          final baseline = _place(before, anchors: anchors);

          final candidates = [...people, ...requests];
          final x = candidates[rnd.nextInt(candidates.length)];
          final touched = {pinnedPerson, ?pinnedRequest, x};
          final after = _diffNotTouching(touched, before, rnd);
          final next = _place(
            after,
            previous: _asPrevious(baseline),
            anchors: anchors,
          );

          for (final entry in anchors.entries) {
            final want = constellationV1AnchorToPoint(entry.value);
            if (next.positions[entry.key] != want) {
              violations.add(
                'seed $seed: placed ${entry.key} left its anchor '
                '(${next.positions[entry.key]} != $want)',
              );
            }
          }
          final problem = _movedOrMissing(x, baseline, next);
          if (problem != null) {
            violations.add('seed $seed: $problem');
          }
          for (final p in _newcomerProblems(before, after, next)) {
            violations.add('seed $seed: $p');
          }
        }
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test(
      'nodes whose placement is still unsaved stay at their pending spot and '
      'free nodes keep their position when other nodes change',
      () {
        final violations = <String>[];
        for (var seed = 0; seed < _caseCount; seed++) {
          final rnd = math.Random(5000 + seed);
          final before = _randomField(rnd);
          final people = before.people.toList()..sort();
          final requests = before.requests.toList()..sort();
          final pendingPerson = people[rnd.nextInt(people.length)];
          final pendingRequest = requests.isEmpty
              ? null
              : requests[rnd.nextInt(requests.length)];
          final pendingTargets = {
            ConstellationAnchorTarget.person(
              pendingPerson,
            ): const ConstellationAnchorPosition(
              xUnits: 2,
              yUnits: -1.5,
              coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
            ),
            if (pendingRequest != null)
              ConstellationAnchorTarget.beacon(
                pendingRequest,
              ): const ConstellationAnchorPosition(
                xUnits: -1.5,
                yUnits: 2,
                coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
              ),
          };
          // Nothing is confirmed by the server: the only placement intent is
          // the unresolved outbox write.
          final desired = desiredAnchorProjection(
            ConstellationAnchorProjection(
              revision: ConstellationAnchorRevision(BigInt.zero),
              anchors: const [],
              pinnedPeers: const [],
              pinnedRequests: const [],
              supportPeers: const [],
              supportEdges: const [],
              serverFilteredBeaconIds: const [],
              serverFilteredBeaconCount: 0,
            ),
            PlacementOutboxState(
              targets: {
                for (final e in pendingTargets.entries)
                  e.key: PlacementTargetState(
                    latestPending: PlacementSlot(
                      op: PlacementOp.upsert(
                        clientOpId: 'op-${e.key.graphNodeId}',
                        clusterId: 'cluster',
                        target: e.key,
                        position: e.value,
                      ),
                      status: PlacementSlotStatus.queued,
                    ),
                  ),
              },
              hasUserPlacements: true,
              generation: 1,
            ),
            now: DateTime.utc(2026, 10, 8, 12),
          );
          final anchors = {
            for (final a in desired.projection.anchors)
              a.target.graphNodeId: a.position,
          };
          final baseline = _place(before, anchors: anchors);

          final candidates = [...people, ...requests];
          final x = candidates[rnd.nextInt(candidates.length)];
          final after = _diffNotTouching({...anchors.keys, x}, before, rnd);
          final next = _place(
            after,
            previous: _asPrevious(baseline),
            anchors: anchors,
          );

          for (final entry in anchors.entries) {
            final want = constellationV1AnchorToPoint(entry.value);
            if (next.positions[entry.key] != want) {
              violations.add(
                'seed $seed: unsaved ${entry.key} left its pending spot '
                '(${next.positions[entry.key]} != $want)',
              );
            }
          }
          final problem = _movedOrMissing(x, baseline, next);
          if (problem != null) {
            violations.add('seed $seed: $problem');
          }
          for (final p in _newcomerProblems(before, after, next)) {
            violations.add('seed $seed: $p');
          }
        }
        expect(violations, isEmpty, reason: violations.take(10).join('\n'));
      },
    );

    test('with unchanged inputs the previous layout is reproduced exactly', () {
      for (var seed = 0; seed < _caseCount; seed++) {
        final field = _randomField(math.Random(2000 + seed));
        final baseline = _place(field);
        final again = _place(field, previous: _asPrevious(baseline));
        expect(again.positions, baseline.positions, reason: 'seed $seed');
      }
    });
  });
}
