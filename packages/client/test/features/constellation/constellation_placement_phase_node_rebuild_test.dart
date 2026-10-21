// A placement phase change (grab, drop, cancel) only matters to the few
// widgets that render the phase. It must not rebuild the graph's node
// subtrees: every node tile is rebuilt per phase change otherwise, which
// stalls the grab and the drop frame at hundreds of nodes.
//
// Work is pinned with a rebuild counter (`debugOnRebuildDirtyWidget`), never
// wall-clock.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_composer_screen_harness.dart';

const _ids = ['a', 'b', 'c', 'd', 'e', 'f'];

bool _isNodesView(Widget widget) =>
    widget.runtimeType.toString() == 'NodesView';

/// The one node the tests grab and move. A moving node is isolated into its
/// own repaint boundary, which re-parents its content and rebuilds it; every
/// other node must stay untouched.
const _movedNodeKey = ValueKey<String>('fr:req-a');

bool _isMovedNode(Widget widget) => widget.key == _movedNodeKey;

/// Rebuilds of any `NodesView` element, or of anything beneath one (except the
/// moved node's own subtree), while [body] runs.
Future<int> _nodeSubtreeRebuildsDuring(Future<void> Function() body) async {
  var rebuilds = 0;
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    var underNodes = _isNodesView(element.widget);
    var underMovedNode = _isMovedNode(element.widget);
    if (!underNodes) {
      element.visitAncestorElements((ancestor) {
        underMovedNode = underMovedNode || _isMovedNode(ancestor.widget);
        underNodes = _isNodesView(ancestor.widget);
        return !underNodes;
      });
    }
    if (underNodes && !underMovedNode) rebuilds++;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilds;
}

final _nodesView = find.byWidgetPredicate((w) => _isNodesView(w));

/// Fails unless the graph mounted its node tiles, so a zero rebuild count
/// cannot come from an empty graph.
void _expectNodeTilesMounted() {
  expect(_nodesView, findsOneWidget, reason: 'the map mounts a NodesView');
  expect(
    find.descendant(of: _nodesView, matching: find.byType(LayoutId)),
    findsAtLeastNWidgets(3),
    reason: 'the graph mounts its node tiles (ego plus visible field nodes)',
  );
}

void main() {
  group('Placement phase changes on the map', () {
    testWidgets(
      'grabbing, then cancelling a placement rebuilds no node subtree',
      (tester) async {
        final cubit = await loadComposerHarnessCubit(
          ComposerHarnessRepository(
            () => composerHarnessField(peers: _ids),
          ),
        );
        final composer = buildComposerHarnessComposer();
        await pumpComposerHarnessScreen(
          tester,
          cubit: cubit,
          composer: composer,
        );
        expect(cubit.state.viewMode, ConstellationViewMode.map);
        _expectNodeTilesMounted();
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.idle,
        );

        final grabRebuilds = await _nodeSubtreeRebuildsDuring(() async {
          cubit.beginDragExisting(
            target: ConstellationAnchorTarget.beacon('req-a'),
          );
          await tester.pumpAndSettle();
        });
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.draggingExisting,
          reason: 'positive control: the phase did change',
        );
        expect(
          grabRebuilds,
          0,
          reason: 'a grab does not rebuild the node tiles',
        );

        final cancelRebuilds = await _nodeSubtreeRebuildsDuring(() async {
          cubit.cancelPlacement();
          await tester.pumpAndSettle();
        });
        expect(
          cubit.state.placementPhase,
          ConstellationPlacementPhase.idle,
          reason: 'positive control: the phase did change back',
        );
        expect(
          cancelRebuilds,
          0,
          reason: 'leaving the placement phase does not rebuild node tiles',
        );
      },
    );

    testWidgets(
      'dropping a grabbed node rebuilds no node subtree',
      (tester) async {
        final cubit = await loadComposerHarnessCubit(
          ComposerHarnessRepository(
            () => composerHarnessField(peers: _ids),
          ),
        );
        final composer = buildComposerHarnessComposer();
        await pumpComposerHarnessScreen(
          tester,
          cubit: cubit,
          composer: composer,
        );
        _expectNodeTilesMounted();
        final target = ConstellationAnchorTarget.beacon('req-a');
        const dropCentre = Offset(240, 180);
        cubit.beginDragExisting(target: target);
        await tester.pumpAndSettle();

        final dropRebuilds = await _nodeSubtreeRebuildsDuring(() async {
          cubit.updateDragPresentation(
            nodeId: 'req-a',
            sceneCentre: dropCentre,
          );
          await cubit.onExistingNodeDrop(
            target: target,
            sceneCentre: dropCentre,
          );
          await tester.pumpAndSettle();
        });
        expect(
          cubit.state.placementPhase,
          isNot(ConstellationPlacementPhase.draggingExisting),
          reason: 'positive control: the drop ended the grab',
        );
        expect(
          dropRebuilds,
          0,
          reason: 'a drop does not rebuild the node tiles',
        );
      },
    );
  });
}
