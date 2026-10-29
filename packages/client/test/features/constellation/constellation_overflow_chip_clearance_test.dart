@TestOn('vm')
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_viewport_overlay.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';

// The Field collision pass reserves one logical pixel around occupied content.
// Keep that clearance in screen space, including when the camera zooms.
const _minimumClearance = 1.0;
const _bobOffsetAtDefaultZoom = Offset(-68, -68);
// A single -100px mouse-wheel event at the Field's 200px scroll scale factor
// takes the recentered 1x camera to exp(100 / 200). Pin the resulting scale
// independently of the camera so a different zoom cannot weaken the fixture.
const _oneWheelStepScale = 1.6487212707001282;

ConstellationField _neighbouringAuthors() {
  final loadedAt = DateTime.utc(2026, 10, 28, 12);
  final revision = ConstellationAnchorRevision(BigInt.one);
  // These saved positions put two authors diagonally next to one another.
  // Their circles are separate; their fixed-size overflow controls need more
  // room than the gap between them, even as the camera zooms in.
  return ConstellationField(
    loadedAt: loadedAt,
    context: '',
    peers: const [ConstellationPerson(id: 'bob', displayName: 'Bob')],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'bob', tier: 1),
    ],
    requests: [
      // The desktop budget shows three requests per author: these totals
      // reproduce the differently sized "+34 more" and "+1 more" controls.
      for (final (author, count) in [('ego', 37), ('bob', 4)])
        for (var i = 0; i < count; i++)
          ConstellationRequest(
            id: '$author-request-$i',
            authorId: author,
            title: 'Request $i by $author',
            status: 0,
            isMine: author == 'ego',
          ),
    ],
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.person('bob'),
          position: const ConstellationAnchorPosition(
            xUnits: -0.4,
            yUnits: -0.4,
            coordinateSpaceVersion: 1,
          ),
          revision: revision,
          placedAt: loadedAt,
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}

// The overlay frame describes the circles that the Field paints. Use the
// circle itself, rather than rejecting a chip in a bounding-box corner.
double _circleClearance(Rect chip, Rect body) {
  final nearest = Offset(
    body.center.dx.clamp(chip.left, chip.right),
    body.center.dy.clamp(chip.top, chip.bottom),
  );
  return (nearest - body.center).distance - body.width / 2;
}

double _rectClearance(Rect a, Rect b) {
  final dx = math.max<double>(0, math.max(a.left - b.right, b.left - a.right));
  final dy = math.max<double>(0, math.max(a.top - b.bottom, b.top - a.bottom));
  return Offset(dx, dy).distance;
}

void main() {
  group('Field overflow chip clearance', () {
    for (final zoomIn in [false, true]) {
      testWidgets(
        zoomIn
            ? 'chips clear both nodes and name labels after one wheel zoom in'
            : 'chips clear both nodes and name labels at recentered default zoom',
        (tester) async {
          final cubit = ConstellationCubit(
            case_: constellationCaseForField(_neighbouringAuthors()),
            viewer: const Profile(id: 'ego', displayName: 'Alice'),
          );
          addTearDown(cubit.close);
          await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
          cubit.toggleSatelliteOverflow('ego');
          final holder = ConstellationPresentationFrameHolder();
          await pumpConstellationBody(
            tester,
            cubit,
            size: const Size(1200, 900),
            locale: const Locale('en'),
            presentationFrameHolder: holder,
          );
          await tester.pumpAndSettle();
          expect(find.text('Show fewer'), findsOneWidget);
          await tester.tap(find.text('Show fewer'));
          await tester.pumpAndSettle();
          expect(cubit.isSatelliteOverflowExpanded('ego'), isFalse);
          await tester.tap(
            find.byKey(TestIds.key(TestIds.constellationCenterOnMe)),
          );
          await tester.pumpAndSettle();
          final defaultScale = cubit.graphController.cameraScale;
          expect(defaultScale, closeTo(1, 0.001));
          final defaultSizes = <String, Size>{
            for (final author in ['ego', 'bob'])
              for (final key in [
                'constellation.overflow.$author',
                'constellation.label.fp:$author',
              ])
                key: tester.getSize(find.byKey(Key(key))),
          };
          if (zoomIn) {
            final overlay = find.byType(ConstellationViewportOverlay);
            // A valid placement may put a chip at the viewport center. Wheel
            // over clear canvas so the event reaches the map beneath it.
            final wheelPosition =
                tester.getCenter(overlay) + const Offset(200, 0);
            final wheelLocal = wheelPosition - tester.getTopLeft(overlay);
            for (final rect in [
              ...holder.frame!.chips.values,
              ...holder.frame!.labels.values,
            ]) {
              expect(rect.contains(wheelLocal), isFalse);
            }
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: wheelPosition,
                scrollDelta: const Offset(0, -100),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              cubit.graphController.cameraScale,
              closeTo(_oneWheelStepScale, 0.000001),
              reason: 'one wheel step must reach the specified zoom level',
            );
          }

          final origin = tester.getTopLeft(
            find.byType(ConstellationViewportOverlay),
          );
          final viewport = tester.getRect(
            find.byType(ConstellationViewportOverlay),
          );
          final chips = <String, Rect>{};
          final labels = <String, Rect>{};
          final bodies = <String, Rect>{};
          for (final author in ['ego', 'bob']) {
            final chip = find.byKey(Key('constellation.overflow.$author'));
            final label = find.byKey(Key('constellation.label.fp:$author'));
            expect(chip, findsOneWidget);
            expect(label, findsOneWidget);
            final hiddenCount = author == 'ego' ? 34 : 1;
            expect(cubit.overflowHiddenCountByAuthor[author], hiddenCount);
            for (final (container, text) in [
              (chip, '+$hiddenCount more'),
              (label, author == 'ego' ? 'Alice' : 'Bob'),
            ]) {
              final caption = find.descendant(
                of: container,
                matching: find.text(text),
              );
              expect(caption, findsOneWidget);
              expect(
                tester.renderObject<RenderParagraph>(caption).didExceedMaxLines,
                isFalse,
                reason: 'the complete caption "$text" must fit its rectangle',
              );
            }
            chips[author] = tester.getRect(chip);
            labels[author] = tester.getRect(label);
            bodies[author] = holder.frame!.bodies['fp:$author']!.shift(origin);
            expect(
              chips[author]!.size,
              defaultSizes['constellation.overflow.$author'],
            );
            expect(
              labels[author]!.size,
              defaultSizes['constellation.label.fp:$author'],
            );
            expect(
              chips[author]!.height,
              greaterThanOrEqualTo(kMinInteractiveDimension),
            );
            expect(chips[author]!.size.isEmpty, isFalse);
            expect(labels[author]!.size.isEmpty, isFalse);
            expect(bodies[author]!.size.isEmpty, isFalse);
            for (final rect in [
              chips[author]!,
              labels[author]!,
              bodies[author]!,
            ]) {
              expect(
                viewport.intersect(rect),
                rect,
                reason: '$author chip, label and circle must be fully visible',
              );
            }
          }
          expect(
            (bodies['ego']!.center - bodies['bob']!.center).distance,
            greaterThan((bodies['ego']!.width + bodies['bob']!.width) / 2),
            reason: 'the neighbouring author circles themselves are separate',
          );
          final delta = bodies['bob']!.center - bodies['ego']!.center;
          final expectedDelta =
              _bobOffsetAtDefaultZoom * (zoomIn ? _oneWheelStepScale : 1);
          expect(delta.dx, closeTo(expectedDelta.dx, 0.1));
          expect(delta.dy, closeTo(expectedDelta.dy, 0.1));
          expect(
            delta.distance,
            lessThan(math.min(chips['ego']!.width, chips['bob']!.width)),
            reason:
                'at both scales the author centers are closer than either '
                'full-size chip is wide, so this remains a tight layout',
          );

          final collisions = <String>[];
          if (_rectClearance(chips['ego']!, chips['bob']!) <
              _minimumClearance) {
            collisions.add(
              'Alice chip ${chips['ego']} lacks 1px clearance from Bob chip '
              '${chips['bob']}',
            );
          }
          for (final chip in chips.entries) {
            for (final author in ['ego', 'bob']) {
              if (_circleClearance(chip.value, bodies[author]!) <
                  _minimumClearance) {
                collisions.add(
                  '${chip.key} chip ${chip.value} lacks 1px clearance from '
                  '$author node ${bodies[author]}',
                );
              }
              if (_rectClearance(chip.value, labels[author]!) <
                  _minimumClearance) {
                collisions.add(
                  '${chip.key} chip ${chip.value} lacks 1px clearance from '
                  '$author name label ${labels[author]}',
                );
              }
            }
          }
          expect(collisions, isEmpty);
        },
      );
    }
  });
}
