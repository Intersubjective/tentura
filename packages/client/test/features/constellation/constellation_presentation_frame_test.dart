import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';

void main() {
  const snapshot = Object();
  const gap = 2.0;
  const minTarget = 48.0;
  const viewport = Size(400, 400);

  ConstellationFrameNodeInput node({
    required String id,
    required Offset centre,
    double bodyDiameter = 40,
    Size labelSize = const Size(80, 20),
    int priority = 2,
    int ring = 0,
    bool labelCandidate = true,
  }) {
    return ConstellationFrameNodeInput(
      id: id,
      centre: centre,
      bodyDiameter: bodyDiameter,
      badgeOverhang: 0,
      labelSize: labelSize,
      priority: priority,
      ring: ring,
      labelCandidate: labelCandidate,
    );
  }

  ConstellationPresentationFrame compute({
    required List<ConstellationFrameNodeInput> nodes,
    List<ConstellationFrameChipInput> chips = const [],
    ConstellationDetailLevel detail = ConstellationDetailLevel.normal,
    bool rtl = false,
  }) {
    return computeConstellationPresentationFrame(
      snapshot: snapshot,
      cameraRevision: 1,
      detail: detail,
      viewport: viewport,
      nodesInPaintOrder: nodes,
      chips: chips,
      gap: gap,
      minTarget: minTarget,
      rtl: rtl,
    );
  }

  group('computeConstellationPresentationFrame', () {
    test('two distant nodes place labels below', () {
      final frame = compute(
        nodes: [
          node(id: 'a', centre: const Offset(100, 100)),
          node(id: 'b', centre: const Offset(300, 100)),
        ],
      );

      expect(frame.labels.length, 2);
      for (final id in ['a', 'b']) {
        final body = frame.bodies[id]!;
        final label = frame.labels[id]!;
        expect(label.top, greaterThan(body.bottom));
        expect(label.center.dx, closeTo(body.center.dx, 0.01));
      }
    });

    test('node near bottom viewport edge places label above', () {
      final centre = Offset(viewport.width / 2, viewport.height - 10);
      final frame = compute(
        nodes: [
          node(id: 'edge', centre: centre),
        ],
      );

      final body = frame.bodies['edge']!;
      final label = frame.labels['edge']!;
      expect(label.bottom, lessThan(body.top));
    });

    test('two close nodes get non-overlapping labels', () {
      final y = 120.0;
      final frame = compute(
        nodes: [
          node(id: 'left', centre: Offset(150, y)),
          node(id: 'right', centre: Offset(180, y)),
        ],
      );

      final leftLabel = frame.labels['left']!;
      final rightLabel = frame.labels['right']!;
      expect(leftLabel.overlaps(rightLabel), isFalse);
    });

    test(
      'overview suppresses Request labels but keeps ego and ring<=1 people',
      () {
        final frame = compute(
          detail: ConstellationDetailLevel.overview,
          nodes: [
            node(
              id: 'ego',
              centre: const Offset(200, 200),
              priority: 1,
              ring: 0,
              labelCandidate: constellationLabelCandidateForDetail(
                detail: ConstellationDetailLevel.overview,
                priority: 1,
                ring: 0,
              ),
            ),
            node(
              id: 'peer',
              centre: const Offset(280, 200),
              priority: 2,
              ring: 1,
              labelCandidate: constellationLabelCandidateForDetail(
                detail: ConstellationDetailLevel.overview,
                priority: 2,
                ring: 1,
              ),
            ),
            node(
              id: 'req',
              centre: const Offset(200, 280),
              priority: 3,
              ring: 0,
              labelCandidate: constellationLabelCandidateForDetail(
                detail: ConstellationDetailLevel.overview,
                priority: 3,
                ring: 0,
              ),
            ),
          ],
        );

        expect(frame.labels.containsKey('ego'), isTrue);
        expect(frame.labels.containsKey('peer'), isTrue);
        expect(frame.labels.containsKey('req'), isFalse);
      },
    );

    test('ego with no room is forced below and listed in forcedLabels', () {
      final frame = computeConstellationPresentationFrame(
        snapshot: snapshot,
        cameraRevision: 1,
        detail: ConstellationDetailLevel.normal,
        viewport: const Size(120, 120),
        nodesInPaintOrder: [
          node(
            id: 'ego',
            centre: const Offset(60, 60),
            priority: 1,
            labelSize: const Size(100, 50),
          ),
        ],
        chips: const [],
        gap: gap,
        minTarget: minTarget,
        rtl: false,
      );

      expect(frame.labels.containsKey('ego'), isTrue);
      expect(frame.forcedLabels, contains('ego'));
    });

    test('chip does not intersect bodies when a free candidate exists', () {
      final author = node(id: 'author', centre: const Offset(80, 80));
      final neighbour = node(id: 'n2', centre: const Offset(320, 320));
      const chipSize = Size(100, 44);
      final frame = compute(
        nodes: [author, neighbour],
        chips: [
          ConstellationFrameChipInput(
            authorId: 'in',
            authorGraphId: 'author',
            size: chipSize,
          ),
        ],
      );

      final chip = frame.chips['in']!;
      for (final body in frame.bodies.values) {
        expect(chip.overlaps(body), isFalse);
      }
    });

    // #459: the overflow chip must never sit on its author's name label.
    // Ego at (200, 150); one body blocks the slot below the label and one
    // blocks the start-side label slot. The chip's end-side candidate then
    // overlaps the label slot below the author, and a chip placed before
    // the label pushes the label out (or, for the ego, the label is forced
    // underneath the chip).
    List<ConstellationFrameNodeInput> crowdedAuthor({required int priority}) {
      return [
        node(
          id: 'author',
          centre: const Offset(200, 150),
          bodyDiameter: 32,
          labelSize: const Size(100, 20),
          priority: priority,
        ),
        node(
          id: 'blockBelow',
          centre: const Offset(200, 212),
          labelSize: Size.zero,
          priority: 3,
          labelCandidate: false,
        ),
        node(
          id: 'blockStart',
          centre: const Offset(120, 150),
          labelSize: Size.zero,
          priority: 3,
          labelCandidate: false,
        ),
      ];
    }

    ConstellationPresentationFrame computeCrowded({required int priority}) {
      return computeConstellationPresentationFrame(
        snapshot: snapshot,
        cameraRevision: 1,
        detail: ConstellationDetailLevel.normal,
        viewport: viewport,
        nodesInPaintOrder: crowdedAuthor(priority: priority),
        chips: const [
          ConstellationFrameChipInput(
            authorId: 'ego',
            authorGraphId: 'author',
            size: Size(100, 44),
          ),
        ],
        gap: gap,
        minTarget: minTarget,
        rtl: false,
        // The live overlay places with cullToViewport: false.
        cullToViewport: false,
      );
    }

    test('ego overflow chip does not cover the ego name label (#459)', () {
      final frame = computeCrowded(priority: 1);

      final chip = frame.chips['ego'];
      final label = frame.labels['author'];
      expect(chip, isNotNull, reason: 'the chip must still be placed');
      expect(label, isNotNull, reason: 'the ego always keeps its label');
      expect(
        chip!.overlaps(label!),
        isFalse,
        reason: 'chip $chip sits on the name label $label',
      );
      for (final entry in frame.bodies.entries) {
        expect(
          chip.overlaps(entry.value),
          isFalse,
          reason: 'chip covers body ${entry.key}',
        );
      }
      // The chip stays next to its author rather than being thrown away.
      final body = frame.bodies['author']!;
      expect(
        (chip.center - body.center).distance,
        lessThan(body.width + chip.width + chip.height),
      );
    });

    test('overflow chip does not cost a person their name label (#459)', () {
      final frame = computeCrowded(priority: 2);

      final chip = frame.chips['ego'];
      final label = frame.labels['author'];
      expect(chip, isNotNull, reason: 'the chip must still be placed');
      expect(
        label,
        isNotNull,
        reason: 'a free label slot exists once the chip moves aside',
      );
      expect(chip!.overlaps(label!), isFalse);
      for (final other in frame.labels.values) {
        expect(chip.overlaps(other), isFalse);
      }
    });

    test('deterministic for identical inputs', () {
      final nodes = [
        node(id: 'a', centre: const Offset(100, 150)),
        node(id: 'b', centre: const Offset(250, 180)),
        node(id: 'c', centre: const Offset(180, 280)),
      ];
      final a = compute(nodes: nodes);
      final b = compute(nodes: nodes);
      const mapEq = MapEquality<GraphNodeId, Rect>();
      expect(mapEq.equals(a.bodies, b.bodies), isTrue);
      expect(mapEq.equals(a.labels, b.labels), isTrue);
      expect(mapEq.equals(a.tapTargets, b.tapTargets), isTrue);
      expect(mapEq.equals(a.chips, b.chips), isTrue);
    });
  });

  group('resolveConstellationTap', () {
    test('label wins over unrelated body at same point', () {
      const p = Offset(200, 240);
      final frame = ConstellationPresentationFrame(
        snapshot: snapshot,
        cameraRevision: 1,
        detail: ConstellationDetailLevel.normal,
        paintOrder: const ['bodyOnly', 'labelNode'],
        bodies: {
          'labelNode': Rect.fromCenter(
            center: const Offset(200, 200),
            width: 40,
            height: 40,
          ),
          'bodyOnly': Rect.fromCenter(
            center: const Offset(200, 230),
            width: 40,
            height: 40,
          ),
        },
        labels: {
          'labelNode': Rect.fromCenter(
            center: p,
            width: 80,
            height: 20,
          ),
        },
        tapTargets: const {},
        chips: const {},
        forcedLabels: const {},
      );
      expect(frame.bodies['bodyOnly']!.contains(p), isTrue);
      expect(resolveConstellationTap(frame, p), 'labelNode');
    });

    test('later paint order wins for overlapping bodies', () {
      final centre = const Offset(200, 200);
      final frame = compute(
        nodes: [
          node(id: 'first', centre: centre),
          node(id: 'second', centre: centre),
        ],
      );
      expect(resolveConstellationTap(frame, centre), 'second');
    });

    test('nearest body centre among overlapping tap targets', () {
      final frame = compute(
        nodes: [
          node(id: 'near', centre: const Offset(200, 200)),
          node(id: 'far', centre: const Offset(230, 200)),
        ],
      );
      final nearTarget = frame.tapTargets['near']!;
      final farTarget = frame.tapTargets['far']!;
      final overlap = nearTarget.intersect(farTarget);
      expect(overlap.isEmpty, isFalse);
      final p = Offset(overlap.center.dx, overlap.top - 2);
      expect(frame.bodies['near']!.contains(p), isFalse);
      expect(frame.bodies['far']!.contains(p), isFalse);
      expect(resolveConstellationTap(frame, p), 'near');
    });

    test('returns null when nothing hit', () {
      final frame = compute(
        nodes: [
          node(id: 'a', centre: const Offset(50, 50)),
        ],
      );
      expect(resolveConstellationTap(frame, const Offset(390, 390)), isNull);
    });

    test('21px outside body radius still hits expanded tap target (R06)', () {
      final centre = const Offset(200, 200);
      final frame = compute(
        nodes: [
          node(id: 'req', centre: centre, bodyDiameter: 40),
        ],
      );
      final body = frame.bodies['req']!;
      final p = body.center + const Offset(21, 0);
      expect(body.contains(p), isFalse);
      expect(frame.tapTargets['req']!.contains(p), isTrue);
      expect(resolveConstellationTap(frame, p), 'req');
    });

    test('overlapping nodes at same centre prefer later paint order (D21)', () {
      final centre = const Offset(200, 200);
      final frame = compute(
        nodes: [
          node(id: 'req-in-1', centre: centre),
          node(id: 'req-in-2', centre: centre),
        ],
      );
      expect(resolveConstellationTap(frame, centre), 'req-in-2');
    });
  });

  group('bare detail below the small zoom (#595)', () {
    test('no node is a label candidate, whatever its priority', () {
      for (var priority = 0; priority <= 3; priority++) {
        for (var ring = 0; ring <= 3; ring++) {
          expect(
            constellationLabelCandidateForDetail(
              detail: ConstellationDetailLevel.bare,
              priority: priority,
              ring: ring,
            ),
            isFalse,
          );
        }
      }
    });

    test('zooming out never adds a candidate', () {
      for (var priority = 0; priority <= 3; priority++) {
        for (var ring = 0; ring <= 3; ring++) {
          bool at(ConstellationDetailLevel detail) =>
              constellationLabelCandidateForDetail(
                detail: detail,
                priority: priority,
                ring: ring,
              );
          if (at(ConstellationDetailLevel.bare)) {
            expect(at(ConstellationDetailLevel.overview), isTrue);
          }
          if (at(ConstellationDetailLevel.overview)) {
            expect(at(ConstellationDetailLevel.normal), isTrue);
          }
        }
      }
    });

    test('places no overflow chip and forces no label', () {
      final frame = computeConstellationPresentationFrame(
        snapshot: snapshot,
        cameraRevision: 1,
        detail: ConstellationDetailLevel.bare,
        viewport: const Size(120, 120),
        nodesInPaintOrder: [
          node(
            id: 'ego',
            centre: const Offset(60, 60),
            priority: 1,
            labelSize: const Size(100, 50),
          ),
        ],
        chips: [
          ConstellationFrameChipInput(
            authorId: 'ego',
            authorGraphId: 'ego',
            size: const Size(40, 20),
          ),
        ],
        gap: gap,
        minTarget: minTarget,
        rtl: false,
      );

      expect(frame.labels, isEmpty);
      expect(frame.forcedLabels, isEmpty);
      expect(frame.chips, isEmpty);
    });

    test('overview forces no label that does not fit', () {
      final frame = computeConstellationPresentationFrame(
        snapshot: snapshot,
        cameraRevision: 1,
        detail: ConstellationDetailLevel.overview,
        viewport: const Size(120, 120),
        nodesInPaintOrder: [
          node(
            id: 'ego',
            centre: const Offset(60, 60),
            priority: 1,
            labelSize: const Size(100, 50),
          ),
        ],
        chips: const [],
        gap: gap,
        minTarget: minTarget,
        rtl: false,
      );

      expect(frame.forcedLabels, isEmpty);
      expect(frame.labels.containsKey('ego'), isFalse);
    });

    test('the cut-off is the same from either direction', () {
      for (final previous in ConstellationDetailLevel.values) {
        expect(
          nextConstellationDetailLevel(0.2, previous),
          ConstellationDetailLevel.bare,
        );
        expect(
          nextConstellationDetailLevel(
            kConstellationBareDetailScale,
            previous,
          ),
          isNot(ConstellationDetailLevel.bare),
        );
      }
      expect(
        nextConstellationDetailLevel(0.77, ConstellationDetailLevel.bare),
        ConstellationDetailLevel.overview,
      );
    });
  });

  group('nextConstellationDetailLevel', () {
    test('scale thresholds and hysteresis band', () {
      expect(
        nextConstellationDetailLevel(0.9, ConstellationDetailLevel.overview),
        ConstellationDetailLevel.normal,
      );
      expect(
        nextConstellationDetailLevel(0.6, ConstellationDetailLevel.normal),
        ConstellationDetailLevel.overview,
      );
      expect(
        nextConstellationDetailLevel(0.77, ConstellationDetailLevel.normal),
        ConstellationDetailLevel.normal,
      );
      expect(
        nextConstellationDetailLevel(0.77, ConstellationDetailLevel.overview),
        ConstellationDetailLevel.overview,
      );
    });
  });
}
