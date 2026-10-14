import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'support/int_graph_controller.dart';

// Runtime lookup keeps the test executable before the public API is added,
// following scene_revision_test.dart's missing-getter convention.
ValueListenable<Offset> _positionListenable(
  GraphController<Node<int>, Edge<Node<int>, int>> controller,
  GraphNodeId id,
) {
  try {
    // ignore: avoid_dynamic_calls -- Assert the not-yet-present public API.
    final Object? value = (controller as dynamic).positionListenableForId(id);
    expect(value, isA<ValueListenable<Offset>>());
    return value! as ValueListenable<Offset>;
    // ignore: avoid_catching_errors -- Turn a missing API into an assertion.
  } on NoSuchMethodError {
    fail('GraphController must expose positionListenableForId(id) as a stable '
        'ValueListenable<Offset> for each live node');
  }
}

void main() {
  const moving = Node<int>(data: 1, size: 40);
  const stationary = Node<int>(data: 2, size: 40);

  GraphController<Node<int>, Edge<Node<int>, int>> createController() {
    final controller = testIntIntGraphController()
      ..reconcileTopology(
        {moving, stationary},
        const {},
        requestLayout: false,
      )
      ..beginNodePresentationDragForId('1', const Offset(100, 100))
      ..beginNodePresentationDragForId('2', const Offset(300, 100));
    return controller;
  }

  group('Per-node position listenables', () {
    test('identity survives position changes and payload replacement', () {
      final controller = createController();
      addTearDown(controller.dispose);
      final movingPosition = _positionListenable(controller, '1');
      final stationaryPosition = _positionListenable(controller, '2');
      expect(movingPosition.value, const Offset(100, 100));
      expect(stationaryPosition.value, const Offset(300, 100));

      controller
        ..beginNodePresentationDragForId('1', const Offset(160, 120))
        ..reconcileTopology(
          {const Node<int>(data: 1, size: 60), stationary},
          const {},
          requestLayout: false,
        );

      expect(_positionListenable(controller, '1'), same(movingPosition));
      expect(_positionListenable(controller, '2'), same(stationaryPosition));
      expect(movingPosition.value, const Offset(160, 120));
      expect(stationaryPosition.value, const Offset(300, 100));
    });

    test('only changed positions notify with the committed scene revision', () {
      final controller = createController();
      addTearDown(controller.dispose);
      final movingPosition = _positionListenable(controller, '1');
      final stationaryPosition = _positionListenable(controller, '2');
      final previousRevision = controller.sceneRevision;
      final topologyRevision = controller.scene.topologyRevision;
      var movingNotifications = 0;
      var stationaryNotifications = 0;
      movingPosition.addListener(() {
        movingNotifications++;
        final snapshot = controller.renderSnapshot;
        expect(controller.sceneRevision, greaterThan(previousRevision));
        expect(snapshot.sceneRevision, controller.sceneRevision);
        expect(snapshot.resolvePosition('1'), ScenePoint(x: 180, y: 140));
        expect(movingPosition.value, const Offset(180, 140));
        expect(snapshot.resolvePosition('2'), ScenePoint(x: 300, y: 100));
        expect(stationaryPosition.value, const Offset(300, 100));
      });
      stationaryPosition.addListener(() => stationaryNotifications++);

      final token = controller.activePresentationTokenForNode('1')!;
      expect(
        controller.updateNodePresentationDrag(token, const Offset(180, 140)),
        isTrue,
      );
      controller.updateNodePresentationDrag(token, const Offset(180, 140));

      expect(movingNotifications, 1);
      expect(stationaryNotifications, 0);
      expect(controller.scene.topologyRevision, topologyRevision);
    });

    test('topology-only changes leave existing position listeners silent', () {
      final controller = createController();
      addTearDown(controller.dispose);
      final first = _positionListenable(controller, '1');
      final second = _positionListenable(controller, '2');
      var firstNotifications = 0;
      var secondNotifications = 0;
      first.addListener(() => firstNotifications++);
      second.addListener(() => secondNotifications++);
      const added = Node<int>(data: 3, size: 40);
      const edge = Edge<Node<int>, int>(
        source: moving,
        destination: stationary,
        data: 1,
      );

      void reconcileWithoutMovingExistingNodes(
        Set<Node<int>> nodes,
        Set<Edge<Node<int>, int>> edges,
      ) {
        final previousTopologyRevision = controller.scene.topologyRevision;
        controller.reconcileTopology(nodes, edges, requestLayout: false);

        expect(
          controller.scene.topologyRevision,
          greaterThan(previousTopologyRevision),
          reason: 'Each reconcile changes node or edge membership',
        );
        expect(_positionListenable(controller, '1'), same(first));
        expect(_positionListenable(controller, '2'), same(second));
        expect(first.value, const Offset(100, 100));
        expect(second.value, const Offset(300, 100));
        expect(controller.getPositionForId('1'), first.value);
        expect(controller.getPositionForId('2'), second.value);
        expect(
          firstNotifications,
          0,
          reason: 'Topology-only changes must not notify unchanged positions',
        );
        expect(
          secondNotifications,
          0,
          reason: 'Topology-only changes must not notify unchanged positions',
        );
      }

      reconcileWithoutMovingExistingNodes({moving, stationary}, {edge});
      reconcileWithoutMovingExistingNodes({moving, stationary}, const {});
      reconcileWithoutMovingExistingNodes(
        {moving, stationary, added},
        const {},
      );
      reconcileWithoutMovingExistingNodes({moving, stationary}, const {});
    });

    test('batched moves publish coherent positions before node listeners run',
        () {
      final controller = createController();
      addTearDown(controller.dispose);
      final first = _positionListenable(controller, '1');
      final second = _positionListenable(controller, '2');
      final previousRevision = controller.sceneRevision;
      final observedRevisions = <int>[];
      void verifyCommittedPositions() {
        observedRevisions.add(controller.sceneRevision);
        expect(first.value, const Offset(160, 140));
        expect(second.value, const Offset(320, 180));
        final snapshot = controller.renderSnapshot;
        expect(snapshot.sceneRevision, controller.sceneRevision);
        expect(snapshot.resolvePosition('1'), ScenePoint(x: 160, y: 140));
        expect(snapshot.resolvePosition('2'), ScenePoint(x: 320, y: 180));
      }

      first.addListener(verifyCommittedPositions);
      second.addListener(verifyCommittedPositions);
      expect(
        controller.updateNodePresentationDrags({
          controller.activePresentationTokenForNode('1')!:
              const Offset(160, 140),
          controller.activePresentationTokenForNode('2')!:
              const Offset(320, 180),
        }),
        2,
      );

      expect(observedRevisions, hasLength(2));
      expect(observedRevisions.first, greaterThan(previousRevision));
      expect(observedRevisions.last, observedRevisions.first);
    });

    test('removal disposes the old listenable and readdition gets a new one',
        () {
      final controller = createController();
      addTearDown(controller.dispose);
      final removedPosition = _positionListenable(controller, '1');
      final survivingPosition = _positionListenable(controller, '2');
      var removedNotifications = 0;
      removedPosition.addListener(() => removedNotifications++);

      controller.reconcileTopology(
        {stationary},
        const {},
        requestLayout: false,
      );
      expect(() => removedPosition.addListener(() {}), throwsFlutterError);
      expect(_positionListenable(controller, '2'), same(survivingPosition));

      controller
        ..reconcileTopology(
          {moving, stationary},
          const {},
          requestLayout: false,
        )
        ..beginNodePresentationDragForId('1', const Offset(220, 240));
      final replacementPosition = _positionListenable(controller, '1');
      expect(replacementPosition, isNot(same(removedPosition)));
      expect(replacementPosition.value, const Offset(220, 240));
      final notificationsAfterReaddition = removedNotifications;
      controller.beginNodePresentationDragForId('1', const Offset(260, 240));
      expect(replacementPosition.value, const Offset(260, 240));
      expect(removedNotifications, notificationsAfterReaddition);
      expect(_positionListenable(controller, '2'), same(survivingPosition));
    });

    test('controller disposal disposes every remaining position listenable',
        () {
      final controller = createController();
      var disposed = false;
      addTearDown(() {
        if (!disposed) controller.dispose();
      });
      final first = _positionListenable(controller, '1');
      final second = _positionListenable(controller, '2');

      controller.dispose();
      disposed = true;

      expect(() => first.addListener(() {}), throwsFlutterError);
      expect(() => second.addListener(() {}), throwsFlutterError);
    });
  });
}
