import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'fixtures/constellation_reference_fixture.dart';

/// Identify the node owned by a content or position-subscription element.
String? _nodeIdForBuildElement(Element element) {
  final widget = element.widget;
  if (widget is GraphNodeWidget) {
    return widget.nodeDetails.graphNodeId;
  }
  if (widget is! ValueListenableBuilder<Offset> &&
      widget is! ListenableBuilder &&
      widget is! AnimatedBuilder) {
    return null;
  }
  final ids = <String>{};
  void collect(Element child) {
    final widget = child.widget;
    if (widget is GraphNodeWidget) {
      ids.add(widget.nodeDetails.graphNodeId);
    }
    child.visitChildren(collect);
  }

  element.visitChildren(collect);
  return ids.length == 1 ? ids.single : null;
}

/// Count one outer node presentation element, rather than counting both its
/// position builder and its retained/nested content as separate node builds.
String? _rebuiltNodeId(Element element, Set<Element> rebuiltElements) {
  final id = _nodeIdForBuildElement(element);
  if (id == null) return null;
  var nested = false;
  element.visitAncestorElements((ancestor) {
    if (rebuiltElements.contains(ancestor) &&
        _nodeIdForBuildElement(ancestor) == id) {
      nested = true;
      return false;
    }
    return true;
  });
  rebuiltElements.add(element);
  return nested ? null : id;
}

List<ConstellationAnchor> _clusterAnchors() => [
  for (final target in [
    ConstellationAnchorTarget.person('am'),
    ConstellationAnchorTarget.beacon('req-am-1'),
  ])
    ConstellationAnchor(
      target: target,
      position: ConstellationAnchorPosition(
        xUnits: target.kind == ConstellationAnchorTargetKind.person ? 4 : 5,
        yUnits: -2,
        coordinateSpaceVersion: 1,
      ),
      revision: ConstellationAnchorRevision(BigInt.one),
      placedAt: DateTime.utc(2026, 9, 9, 12),
    ),
];

void main() {
  group('Constellation position and membership rebuilds', () {
    testWidgets('geometry revisions do not rebuild the canvas body', (
      tester,
    ) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);
      await pumpConstellationBody(tester, cubit);
      await tester.pumpAndSettle();
      final bodyBuilder = tester.element(
        find.ancestor(
          of: find.byWidgetPredicate(
            (widget) => widget is GraphView<NodeDetails, EdgeDetails>,
          ),
          matching: find.byType(
            BlocBuilder<ConstellationCubit, ConstellationState>,
          ),
        ),
      );
      var bodyBuilds = 0;
      final previousCallback = debugOnRebuildDirtyWidget;
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousCallback?.call(element, builtOnce);
        if (identical(element, bodyBuilder)) bodyBuilds++;
      };
      // Positive control proves this counter observes the mounted body builder.
      cubit.selectPerson('am');
      await tester.pumpAndSettle();
      expect(bodyBuilds, greaterThan(0));
      bodyBuilds = 0;
      final previous = cubit.state;
      final topologyRevision = cubit.graphController.scene.topologyRevision;
      final emitted = cubit.stream.first;
      cubit.requestConstellationLayoutForTest();
      expect(
        await emitted,
        previous.copyWith(graphRevision: previous.graphRevision + 1),
      );
      await tester.pump();
      await tester.pump();
      expect(cubit.graphController.scene.topologyRevision, topologyRevision);
      expect(
        bodyBuilds,
        0,
        reason:
            'A graphRevision-only emission must leave the mounted body unbuilt',
      );
    });

    testWidgets(
      'one person drag move rebuilds exactly its pinned cluster once',
      (tester) async {
        final builds = <String, int>{};
        final rebuiltElements = <Element>{};
        var canvasBuilds = 0;
        final previousCallback = debugOnRebuildDirtyWidget;
        addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousCallback?.call(element, builtOnce);
          if (element.widget is GraphView<NodeDetails, EdgeDetails>) {
            canvasBuilds++;
          }
          final id = _rebuiltNodeId(element, rebuiltElements);
          if (id != null) {
            builds.update(id, (count) => count + 1, ifAbsent: () => 1);
          }
        };
        final cubit = await loadReferenceCubit(
          field: constellationReferenceField(anchors: _clusterAnchors()),
        );
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: const Size(1200, 900),
        );
        await tester.pumpAndSettle();
        final controller = cubit.graphController;
        final nodeFinder = find.byType(GraphNodeWidget);
        final mountedIds = tester
            .widgetList<GraphNodeWidget>(nodeFinder)
            .map((widget) => widget.nodeDetails.graphNodeId)
            .toSet();
        const clusterIds = {'fp:am', 'fr:req-am-1'};
        expect(mountedIds, containsAll(clusterIds));
        final unrelatedIds = mountedIds.difference(clusterIds);
        expect(unrelatedIds, isNotEmpty);
        for (final id in mountedIds) {
          expect(builds[id], greaterThan(0), reason: 'Counter observes $id');
        }

        cubit.beginDragExisting(
          target: ConstellationAnchorTarget.person('am'),
        );
        await tester.pumpAndSettle();
        final centres = {
          for (final id in mountedIds) id: controller.getPositionForId(id),
        };
        final topologyRevision = controller.scene.topologyRevision;
        final layoutCount = controller.relayoutInvocationCount;
        final cameraRevision = controller.cameraRevision.value;
        Offset paintedCentre(String id) => tester.getCenter(
          find.byWidgetPredicate(
            (widget) =>
                widget is GraphNodeWidget &&
                widget.nodeDetails.graphNodeId == id,
          ),
        );
        final paintedCentres = {
          for (final id in mountedIds) id: paintedCentre(id),
        };
        builds.clear();
        rebuiltElements.clear();
        canvasBuilds = 0;

        const delta = Offset(24, 16);
        cubit.updateDragPresentation(
          nodeId: 'am',
          sceneCentre: centres['fp:am']! + delta,
        );
        await tester.pump();

        for (final id in clusterIds) {
          expect(controller.getPositionForId(id), centres[id]! + delta);
          expect(
            (paintedCentre(id) - paintedCentres[id]!).distance,
            greaterThan(0),
            reason: 'The mounted node $id must follow its presentation',
          );
        }
        for (final id in unrelatedIds) {
          expect(controller.getPositionForId(id), centres[id]);
          expect(paintedCentre(id), paintedCentres[id]);
        }
        expect(controller.scene.topologyRevision, topologyRevision);
        expect(controller.relayoutInvocationCount, layoutCount);
        expect(controller.cameraRevision.value, cameraRevision);
        final expectedAffectedIds = <String>{'fp:am', 'fr:req-am-1'};
        final expectedBuildCounts = {
          for (final id in mountedIds)
            id: expectedAffectedIds.contains(id) ? 1 : 0,
        };
        final actualBuildCounts = {
          for (final id in mountedIds) id: builds[id] ?? 0,
          ...builds,
        };
        expect(
          builds.keys.toSet(),
          expectedAffectedIds,
          reason: 'The dragged cluster must be the complete affected-node set',
        );
        expect(
          actualBuildCounts,
          expectedBuildCounts,
          reason:
              'Each dragged node must rebuild exactly once and every other node zero times',
        );
        expect(canvasBuilds, 0, reason: 'A move must not rebuild GraphView');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
