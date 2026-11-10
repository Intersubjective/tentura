import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_rearrange_all.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_path_resolution.dart';

/// «Rearrange everyone» with a small tagged roster: each tag gets one compact
/// area of its own, the areas do not overlap, untagged people stay outside
/// every area, and a person with two tags sits between those tag centres.
///
/// Roster: tag A = Boris, Dima; tag B = Nova, Carol; tag C = Boris only;
/// two untagged people. No magnets.

const _ego = 'ego';
const _boris = 'boris';
const _dima = 'dima';
const _nova = 'nova';
const _carol = 'carol';
const _untagged = ['ulya', 'uma'];
const _tagA = 'tag-a';
const _tagB = 'tag-b';
const _spacing = 16.0;
const _gap = _spacing;
const _nodeSize = (width: 64.0, height: 64.0);

const _everyone = {_boris, _dima, _nova, _carol, 'ulya', 'uma'};

ConstellationPlacedLayoutInput _input({
  required String thirdTagId,
  ConstellationViewportClass viewportClass =
      ConstellationViewportClass.expanded,
}) {
  final peers = {..._everyone, _ego};
  final paths = resolveConstellationPaths(
    egoId: _ego,
    visiblePeerIds: peers,
    holderIds: peers,
    edges: [
      for (final id in _everyone) (src: _ego, dst: id, tier: 1),
    ],
  );
  return (
    egoId: _ego,
    paths: paths,
    automaticKeptPeerIds: _everyone,
    pinnedPersonIds: const <String>{},
    pinnedRequestIds: const <String>{},
    supportPersonIds: const <String>{},
    anchorByNodeId: const <String, ConstellationAnchorPosition>{},
    priorHints: null,
    nodeSizes: <String, ConstellationSize>{
      for (final id in peers) id: _nodeSize,
    },
    satelliteRequestIdsByAuthor: const <String, List<String>>{},
    requestAuthorById: const <String, String>{},
    egoOwnRequestIds: const <String>{},
    spacing: _spacing,
    maxHops: 3,
    viewportClass: viewportClass,
    footprints: const <String, ConstellationFootprint>{},
    rearrangeOwnTagPeopleByTagId: {
      _tagA: {_boris, _dima},
      _tagB: {_nova, _carol},
      thirdTagId: {_boris},
    },
    rearrangeTagMagnetsByTagId: const <String, ConstellationPoint>{},
  );
}

double _dist(ConstellationPoint a, ConstellationPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Tag-area radius the tag staging uses: 2.5 × √members × (node + spacing).
double _radius(int memberCount) =>
    2.5 *
    math.sqrt(memberCount) *
    (math.max(_nodeSize.width, _nodeSize.height) + _spacing);

final _rA = _radius(2);
final _rB = _radius(2);
final _rC = _radius(1);

void _expectCompactAndSeparate(ConstellationRearrangement result) {
  final pos = result.layout.positions;
  final cA = result.tagCentres[_tagA];
  final cB = result.tagCentres[_tagB];
  expect(cA, isNotNull, reason: 'tag A gets an area');
  expect(cB, isNotNull, reason: 'tag B gets an area');

  expect(
    _dist(pos[_nova]!, pos[_carol]!),
    lessThan(_rB),
    reason: 'Nova and Carol (tag B only) sit together in one compact area',
  );
  expect(
    _dist(cA!, cB!),
    greaterThan(_rA + _rB + _gap),
    reason: 'tag A and tag B areas are separate, with a gap between them',
  );
}

void main() {
  group('Rearrange everyone gives each tag one compact, separate area', () {
    test('a tag whose two members carry only that tag is compact', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'tag-c'),
      );
      final pos = result.layout.positions;
      expect(_dist(pos[_nova]!, pos[_carol]!), lessThan(_rB));
    });

    test('two tag areas do not overlap', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'tag-c'),
      );
      final cA = result.tagCentres[_tagA]!;
      final cB = result.tagCentres[_tagB]!;
      expect(_dist(cA, cB), greaterThan(_rA + _rB + _gap));
    });

    test('single-tag members sit inside their own area, nearer it than the '
        'other', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'tag-c'),
      );
      final pos = result.layout.positions;
      final cA = result.tagCentres[_tagA]!;
      final cB = result.tagCentres[_tagB]!;

      expect(
        _dist(pos[_dima]!, cA),
        lessThanOrEqualTo(_rA + 1),
        reason: 'Dima',
      );
      expect(
        _dist(pos[_dima]!, cA),
        lessThan(_dist(pos[_dima]!, cB)),
        reason: 'Dima is nearer tag A than tag B',
      );
      for (final id in [_nova, _carol]) {
        expect(_dist(pos[id]!, cB), lessThanOrEqualTo(_rB + 1), reason: id);
        expect(
          _dist(pos[id]!, cB),
          lessThan(_dist(pos[id]!, cA)),
          reason: '$id is nearer tag B than tag A',
        );
      }
    });

    test('untagged people stay outside every tag area', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'tag-c'),
      );
      final pos = result.layout.positions;
      final radii = {_tagA: _rA, _tagB: _rB, 'tag-c': _rC};
      for (final id in _untagged) {
        for (final MapEntry(key: tag, value: r) in radii.entries) {
          final centre = result.tagCentres[tag];
          expect(centre, isNotNull, reason: '$tag gets an area');
          expect(
            _dist(pos[id]!, centre!),
            greaterThanOrEqualTo(r),
            reason: '$id is outside $tag',
          );
        }
      }
    });

    test('a person with two tags sits between those tag centres', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'tag-c'),
      );
      final cA = result.tagCentres[_tagA]!;
      final cC = result.tagCentres['tag-c']!;
      final mid = (x: (cA.x + cC.x) / 2, y: (cA.y + cC.y) / 2);
      expect(
        _dist(result.layout.positions[_boris]!, mid),
        lessThanOrEqualTo(64),
      );
    });

    test('on a phone the areas are still compact and separate', () {
      _expectCompactAndSeparate(
        computeConstellationRearrangeAll(
          _input(
            thirdTagId: 'tag-c',
            viewportClass: ConstellationViewportClass.compact,
          ),
        ),
      );
    });

    test('an automatic third tag leaves the person a single-tag member', () {
      final result = computeConstellationRearrangeAll(
        _input(thirdTagId: 'auto:mutualContact'),
      );
      _expectCompactAndSeparate(result);
      final pos = result.layout.positions;
      final cA = result.tagCentres[_tagA]!;
      final cB = result.tagCentres[_tagB]!;
      expect(
        result.tagCentres.keys.where((id) => id.startsWith('auto:')),
        isEmpty,
        reason: 'an automatic tag forms no area of its own',
      );
      expect(_dist(pos[_boris]!, cA), lessThanOrEqualTo(_rA + 1));
      expect(
        _dist(pos[_boris]!, cA),
        lessThan(_dist(pos[_boris]!, cB)),
        reason: 'Boris belongs to tag A alone',
      );
      // As a single-tag member of A, Boris joins Dima in A's one compact
      // group instead of sitting between A and another centre.
      expect(
        _dist(pos[_boris]!, pos[_dima]!),
        lessThan(_rA),
        reason: 'Boris and Dima (tag A only) sit together in one compact area',
      );
    });
  });
}
