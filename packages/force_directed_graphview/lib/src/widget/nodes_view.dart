import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// { @nodoc }
class NodesView extends StatelessWidget {
  /// { @nodoc }
  const NodesView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final configuration = InheritedConfiguration.configurationOf(context);
    final scope = GraphSceneRenderScope.membershipOf(context);

    return _NodesLayers(
      contents: {
        for (final id in scope.orderedNodeIds)
          id: configuration.nodeBuilder.build(
            context,
            scope.snapshot.topology.nodesById[id]!.payload,
          ),
      },
    );
  }
}

/// Paints all resting nodes into ONE shared repaint boundary that is laid out
/// only when a resting node's position changes, and the dragged nodes into a
/// layer of their own above it. A node keeps its state across the move
/// between the two layers through a [GlobalKey].
class _NodesLayers extends StatefulWidget {
  const _NodesLayers({required this.contents});

  final Map<GraphNodeId, Widget> contents;

  @override
  State<_NodesLayers> createState() => _NodesLayersState();
}

class _NodesLayersState extends State<_NodesLayers> {
  final _keys = <GraphNodeId, GlobalKey>{};
  final _restingTiles = <GraphNodeId, ({Widget child, LayoutId tile})>{};
  final _restingPositions = _RestingPositions();

  GraphController<dynamic, dynamic>? _controller;
  Set<GraphNodeId> _dragged = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = InheritedConfiguration.controllerOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onSceneChanged);
      _controller = controller..addListener(_onSceneChanged);
      _restingPositions.controller = controller;
      _dragged = _currentDragged();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onSceneChanged);
    _restingPositions.dispose();
    super.dispose();
  }

  Set<GraphNodeId> _currentDragged() =>
      _controller!.renderSnapshot.presentation.overrides.keys.toSet();

  void _onSceneChanged() {
    final dragged = _currentDragged();
    if (dragged.length != _dragged.length || !dragged.containsAll(_dragged)) {
      setState(() => _dragged = dragged);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = GraphSceneRenderScope.paintOrderOf(context);
    final controller = InheritedConfiguration.controllerOf(context);
    final ordered = scope.orderedNodeIds;
    _keys.removeWhere((id, _) => !widget.contents.containsKey(id));

    _restingTiles.removeWhere((id, _) => !widget.contents.containsKey(id));

    LayoutId wrap(GraphNodeId id, {required bool isolate}) {
      final child = widget.contents[id]!;
      final content = KeyedSubtree(
        key: _keys.putIfAbsent(id, GlobalKey.new),
        child: child,
      );
      if (isolate) {
        _restingTiles.remove(id);
        return LayoutId(
          key: ValueKey<String>(id),
          id: id,
          child: RepaintBoundary(
            child: _RepaintOnTick(listenable: controller, child: content),
          ),
        );
      }
      // Reuse the tile while the node content is unchanged, so a layer change
      // elsewhere does not rebuild resting tiles.
      final cached = _restingTiles[id];
      if (cached != null && identical(cached.child, child)) return cached.tile;
      final tile = LayoutId(key: ValueKey<String>(id), id: id, child: content);
      _restingTiles[id] = (child: child, tile: tile);
      return tile;
    }

    final resting = [
      for (final id in ordered)
        if (!_dragged.contains(id)) id,
    ];
    final dragged = [
      for (final id in ordered)
        if (_dragged.contains(id)) id,
    ];
    _restingPositions.setNodeIds(resting);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomMultiChildLayout(
            delegate: _NodesLayoutDelegate(
              controller: controller,
              relayout: _restingPositions,
              orderedNodeIds: resting,
            ),
            children: [for (final id in resting) wrap(id, isolate: false)],
          ),
        ),
        CustomMultiChildLayout(
          delegate: _NodesLayoutDelegate(
            controller: controller,
            relayout: controller,
            orderedNodeIds: dragged,
          ),
          children: [for (final id in dragged) wrap(id, isolate: true)],
        ),
      ],
    );
  }
}

/// Repaints its subtree on every [listenable] tick, so a dragged node keeps
/// painting on each drag frame inside its own repaint boundary.
class _RepaintOnTick extends SingleChildRenderObjectWidget {
  const _RepaintOnTick({required this.listenable, super.child});

  final Listenable listenable;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRepaintOnTick(listenable);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderRepaintOnTick renderObject,
  ) =>
      renderObject.setListenable(listenable);
}

class _RenderRepaintOnTick extends RenderProxyBox {
  _RenderRepaintOnTick(this._listenable);

  Listenable _listenable;

  void setListenable(Listenable value) {
    if (identical(value, _listenable)) {
      return;
    }
    if (attached) {
      _listenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _listenable = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _listenable.removeListener(markNeedsPaint);
    super.detach();
  }
}

/// Notifies only when the position of one of its nodes changed, so a layer of
/// resting nodes is not laid out again by unrelated scene changes.
class _RestingPositions extends ChangeNotifier {
  GraphController<dynamic, dynamic>? controller;
  List<GraphNodeId> _nodeIds = const [];
  List<double> _signature = const [];
  GraphController<dynamic, dynamic>? _listening;

  void setNodeIds(List<GraphNodeId> value) {
    _nodeIds = value;
    _signature = _read();
    if (!identical(_listening, controller)) {
      _listening?.removeListener(_onChanged);
      _listening = controller?..addListener(_onChanged);
    }
  }

  List<double> _read() {
    final snapshot = controller!.renderSnapshot;
    final result = <double>[];
    for (final id in _nodeIds) {
      final point = snapshot.resolvePosition(id);
      result
        ..add(point?.x ?? double.nan)
        ..add(point?.y ?? double.nan);
    }
    return result;
  }

  void _onChanged() {
    final next = _read();
    if (!listEquals(next, _signature)) {
      _signature = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _listening?.removeListener(_onChanged);
    super.dispose();
  }
}

class _NodesLayoutDelegate extends MultiChildLayoutDelegate {
  _NodesLayoutDelegate({
    required this.controller,
    required Listenable relayout,
    required this.orderedNodeIds,
  }) : super(relayout: relayout);

  /// Positions are read at layout time, so a position-only scene change
  /// relays out without rebuilding this widget.
  final GraphController<dynamic, dynamic> controller;
  final List<GraphNodeId> orderedNodeIds;

  @override
  void performLayout(Size size) {
    final snapshot = controller.renderSnapshot;
    for (final id in orderedNodeIds) {
      final sceneNode = snapshot.topology.nodesById[id];
      final point = snapshot.resolvePosition(id);
      if (sceneNode == null || point == null) {
        continue;
      }
      final sizeSquare = Size.square(sceneNode.size.width);
      layoutChild(id, BoxConstraints.tight(sizeSquare));
      positionChild(
        id,
        Offset(point.x, point.y) - sizeSquare.center(Offset.zero),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _NodesLayoutDelegate oldDelegate) =>
      controller != oldDelegate.controller ||
      !listEquals(orderedNodeIds, oldDelegate.orderedNodeIds);
}
