@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_scene_controller.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import 'fixtures/constellation_reference_fixture.dart';

const _request = 'fr:req-sm-1';
const _author = 'fp:sm';

Offset? _at(ConstellationCubit cubit, String graphId) =>
    cubit.graphController.getPositionOrNullForId(graphId);

/// Where the accepted layout puts [graphId].
Offset _laidOut(ConstellationCubit cubit, String graphId) {
  final point =
      cubit.graphController.renderSnapshot.layout!.positions[graphId]!;
  return Offset(point.x, point.y);
}

/// Hides every Request (none has a location) and settles.
Future<void> _hideRequests(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  cubit.setFilterLocation(LocationFilter.hasLocation);
  await tester.pumpAndSettle();
  expect(cubit.graphController.nodePayloadForId(_request), isNull);
  expect(
    cubit.graphController.nodePayloadForId(_author),
    isNotNull,
    reason: 'a direct contact stays on the field without Requests',
  );
}

/// Shows the Requests again and pumps the layout and its transition frame by
/// frame; returns every displayed position of [_request], the first one taken
/// right after the Request re-entered the field.
Future<List<Offset>> _showRequests(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  cubit.setFilterLocation(LocationFilter.any);
  final start = _at(cubit, _request);
  expect(start, isNotNull, reason: 'a new Request is drawn at once');
  expect(start, _at(cubit, _author), reason: 'it starts on its author');
  final path = [start!];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    path.add(_at(cubit, _request)!);
  }
  await tester.pumpAndSettle();
  path.add(_at(cubit, _request)!);
  return path;
}

void main() {
  group('beaconSpawnPositions', () {
    const author = FieldPersonNode(person: kRefEgo, ring: 0, isKept: true);
    const kept = FieldBeaconNode(
      request: ConstellationRequest(
        id: 'kept',
        authorId: 'ego',
        title: 'kept',
        status: 0,
      ),
    );
    const arriving = FieldBeaconNode(
      request: ConstellationRequest(
        id: 'new',
        authorId: 'ego',
        title: 'new',
        status: 0,
      ),
    );
    const orphan = FieldBeaconNode(
      request: ConstellationRequest(
        id: 'orphan',
        authorId: 'nobody',
        title: 'orphan',
        status: 0,
      ),
    );
    GraphSceneSnapshot<NodeDetails, EdgeDetails> snapshot(
      List<NodeDetails> nodes,
      Map<String, ScenePoint> seeds,
    ) => GraphSceneSnapshot(
      topology: GraphTopology.fromEntries(
        nodes: [
          for (final node in nodes)
            GraphSceneNode(
              id: node.graphNodeId,
              payload: node,
              size: SceneSize(width: 40, height: 40),
            ),
        ],
        edges: const [],
      ),
      seedPositions: seeds,
    );

    test('seeds only new beacons, on their author', () {
      final positions = ConstellationSceneController.beaconSpawnPositions(
        nodes: {author, kept, arriving},
        previous: snapshot(
          [author, kept],
          {
            'fp:ego': ScenePoint(x: 10, y: 20),
            'fr:kept': ScenePoint(x: 90, y: 90),
          },
        ),
        canvasCentre: const Offset(500, 500),
      );
      expect(positions, {'fr:new': const Offset(10, 20)});
    });

    test('a beacon whose author is not on the field yet starts at the '
        'canvas centre, or is not seeded before the canvas is known', () {
      final previous = snapshot([], {});
      expect(
        ConstellationSceneController.beaconSpawnPositions(
          nodes: {author, arriving, orphan},
          previous: previous,
          canvasCentre: const Offset(500, 500),
        ),
        {
          'fr:new': const Offset(500, 500),
          'fr:orphan': const Offset(500, 500),
        },
      );
      expect(
        ConstellationSceneController.beaconSpawnPositions(
          nodes: {author, arriving},
          previous: previous,
        ),
        isEmpty,
      );
    });
  });

  group('A Request entering the field', () {
    testWidgets('springs out from under its author into its place, '
        'again after every filter off/on', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();

      for (var round = 0; round < 2; round++) {
        await _hideRequests(tester, cubit);
        final path = await _showRequests(tester, cubit);
        final author = path.first;
        final target = path.last;

        expect(target, _laidOut(cubit, _request), reason: 'it lands in place');
        expect((target - author).distance, greaterThan(20));
        final between = path.where(
          (p) =>
              (p - author).distance > 1 &&
              (p - target).distance > 1 &&
              (p - author).distance < (target - author).distance,
        );
        expect(
          between.length,
          greaterThan(5),
          reason: 'it moves to its place over several frames, not in a jump',
        );
        // The way out only moves away from the author.
        var last = 0.0;
        for (final p in path) {
          final d = (p - author).distance;
          expect(d, greaterThanOrEqualTo(last - 0.5));
          last = d;
        }
      }
    });

    testWidgets('paints beneath its author only while it springs out', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit, size: const Size(1200, 900));
      await tester.pumpAndSettle();
      final controller = cubit.graphController;
      List<String> painted() => controller.orderedRenderNodeIds(
        controller.renderSnapshot,
        configuredPaintOrder: cubit.orderedNodeIdsForPaint(),
      );
      final before = painted();
      expect(
        before.indexOf(_request),
        greaterThan(before.indexOf(_author)),
        reason: 'precondition: a settled Request paints above its author',
      );

      await _hideRequests(tester, cubit);
      cubit.setFilterLocation(LocationFilter.any);
      expect(controller.spawningNodeIds, contains(_request));
      final spawning = painted();
      expect(spawning.indexOf(_request), lessThan(spawning.indexOf(_author)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      final moving = painted();
      expect(moving.indexOf(_request), lessThan(moving.indexOf(_author)));

      await tester.pumpAndSettle();
      expect(controller.spawningNodeIds, isEmpty);
      final settled = painted();
      expect(
        settled.indexOf(_request),
        greaterThan(settled.indexOf(_author)),
        reason: 'once in place it paints above its author again',
      );
    });

    testWidgets('with reduced motion lands in its place in one step', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();

      await _hideRequests(tester, cubit);
      final path = await _showRequests(tester, cubit);
      expect(path.last, _laidOut(cubit, _request));
      expect(cubit.graphController.spawningNodeIds, isEmpty);
      expect(
        path.toSet(),
        {path.first, path.last},
        reason: 'no tween: only the spawn point and the final place',
      );
    });
  });
}
