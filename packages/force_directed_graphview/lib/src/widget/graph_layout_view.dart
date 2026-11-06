import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/widget/edges_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';
import 'package:force_directed_graphview/src/widget/labels_view.dart';
import 'package:force_directed_graphview/src/widget/nodes_view.dart';

/// One immutable scene capture shared by paint and hit testing for a frame.
class GraphSceneRenderScope extends InheritedModel<bool> {
  /// { @nodoc }
  const GraphSceneRenderScope({
    required this.snapshot,
    required this.orderedNodeIds,
    this.layoutChromeGeneration = 0,
    required super.child,
    super.key,
  });

  /// Scene revision captured once per layout pass.
  final GraphSceneSnapshot<Object?, Object?> snapshot;

  /// Visible node ids in paint/hit order (later ids are on top).
  final List<GraphNodeId> orderedNodeIds;

  /// Increments when [GraphViewConfiguration.layoutChromeListenable] notifies
  /// without a scene topology / paint-order change, so [NodesView] still
  /// rebuilds (resting tiles cache `identical` child widgets otherwise).
  final int layoutChromeGeneration;

  /// { @nodoc }
  static GraphSceneRenderScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GraphSceneRenderScope>();
    assert(scope != null, 'GraphSceneRenderScope not found');
    return scope!;
  }

  /// Scene membership and payloads, independent of position-only changes.
  static GraphSceneRenderScope membershipOf(BuildContext context) =>
      InheritedModel.inheritFrom<GraphSceneRenderScope>(context, aspect: true)!;

  /// Paint order only; position-only snapshot changes do not notify.
  static GraphSceneRenderScope paintOrderOf(BuildContext context) =>
      InheritedModel.inheritFrom<GraphSceneRenderScope>(context, aspect: false)!;

  @override
  bool updateShouldNotify(GraphSceneRenderScope oldWidget) =>
      snapshot != oldWidget.snapshot ||
      orderedNodeIds != oldWidget.orderedNodeIds ||
      layoutChromeGeneration != oldWidget.layoutChromeGeneration;

  @override
  bool updateShouldNotifyDependent(
    GraphSceneRenderScope oldWidget,
    Set<bool> dependencies,
  ) =>
      (dependencies.contains(true) &&
          (layoutChromeGeneration != oldWidget.layoutChromeGeneration ||
              snapshot.topology != oldWidget.snapshot.topology ||
              !setEquals(
                orderedNodeIds.toSet(),
                oldWidget.orderedNodeIds.toSet(),
              ))) ||
      (dependencies.contains(false) &&
          !listEquals(orderedNodeIds, oldWidget.orderedNodeIds));
}

/// { @nodoc }
class GraphLayoutView extends StatefulWidget {
  /// { @nodoc }
  const GraphLayoutView({
    super.key,
  });

  @override
  State<GraphLayoutView> createState() => _GraphLayoutViewState();
}

class _GraphLayoutViewState extends State<GraphLayoutView> {
  Listenable? _layoutChromeListenable;
  VoidCallback? _layoutChromeListener;
  var _layoutChromeGeneration = 0;

  @override
  void dispose() {
    _removeLayoutChromeListener();
    super.dispose();
  }

  void _removeLayoutChromeListener() {
    final listenable = _layoutChromeListenable;
    final listener = _layoutChromeListener;
    if (listenable != null && listener != null) {
      listenable.removeListener(listener);
    }
    _layoutChromeListenable = null;
    _layoutChromeListener = null;
  }

  void _syncLayoutChromeListener(Listenable? next) {
    if (identical(next, _layoutChromeListenable)) {
      return;
    }
    _removeLayoutChromeListener();
    _layoutChromeListenable = next;
    if (next == null) {
      return;
    }
    void listener() {
      setState(() {
        _layoutChromeGeneration++;
      });
    }

    _layoutChromeListener = listener;
    next.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final configuration = InheritedConfiguration.configurationOf(context);
    final controller = InheritedConfiguration.controllerOf(context);
    _syncLayoutChromeListener(configuration.layoutChromeListenable);
    final backgroundBuilder = configuration.canvasBackgroundBuilder;
    final builder = configuration.builder;

    Widget result = AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.canLayout) {
          // Not zero-size: InteractiveViewer asserts on an empty child once
          // the person zooms or pans the still-empty graph (#464).
          return SizedBox.fromSize(size: controller.emptySceneSize);
        }

        final snapshot = controller.renderSnapshot;
        final orderedNodeIds = controller.orderedRenderNodeIds(
          snapshot,
          configuredPaintOrder: configuration.nodePaintOrder,
        );

        return GraphSceneRenderScope(
          snapshot: snapshot,
          orderedNodeIds: orderedNodeIds,
          layoutChromeGeneration: _layoutChromeGeneration,
          child: SizedBox.fromSize(
            size: controller.canvasSize,
            // Camera transforms reuse the whole scene's layers. Geometry and
            // style changes still invalidate the affected descendants.
            child: RepaintBoundary(
              child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (backgroundBuilder != null)
                        RepaintBoundary(
                          child: backgroundBuilder(context),
                        ),
                      const EdgesView(),
                      const LabelsView(),
                      const NodesView(),
                    ],
                  )),
            ),
          ),
        );
      },
    );

    if (builder != null) {
      result = builder(context, result);
    }

    return result;
  }
}
