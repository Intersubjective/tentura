import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// Paints the edges that do not touch a dragged node into a cached repaint
/// boundary that repaints only when one of their endpoints moves, the edge
/// style changes or the topology changes, and the incident edges into a live
/// boundary above it that repaints on every controller tick.
class EdgesView extends StatefulWidget {
  /// { @nodoc }
  const EdgesView({
    super.key,
  });

  @override
  State<EdgesView> createState() => _EdgesViewState();
}

class _EdgesViewState extends State<EdgesView> {
  final _cachedPositions = _CachedEdgePositions();
  final _pictures = _EdgePictureCache();

  GraphController<dynamic, dynamic>? _controller;
  Set<GraphNodeId> _dragged = const {};
  Listenable? _restyle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = InheritedConfiguration.controllerOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onSceneChanged);
      _controller = controller..addListener(_onSceneChanged);
      _cachedPositions.controller = controller;
      _dragged = _currentDragged();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onSceneChanged);
    _restyle?.removeListener(_pictures.clear);
    _cachedPositions.dispose();
    _pictures.dispose();
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
    final controller = InheritedConfiguration.controllerOf(context);
    final configuration = InheritedConfiguration.configurationOf(context);
    final topology =
        GraphSceneRenderScope.membershipOf(context).snapshot.topology;
    final extraRepaint = switch (configuration.edgePainter) {
      AnimatedEdgePainter(:final animation) => animation,
      RepaintingEdgePainter(:final repaint) => repaint,
      _ => null,
    };
    _cachedPositions.setEdges(topology, _dragged);
    // A restyle notification or a new painter invalidates every cached edge.
    if (!identical(extraRepaint, _restyle)) {
      _restyle?.removeListener(_pictures.clear);
      _restyle = extraRepaint?..addListener(_pictures.clear);
    }
    if (!identical(configuration.edgePainter, _pictures.edgePainter)) {
      _pictures
        ..clear()
        ..edgePainter = configuration.edgePainter;
    }

    Widget layer(_EdgesPainter painter) =>
        RepaintBoundary(child: CustomPaint(painter: painter));

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          layer(
            _EdgesPainter(
              controller: controller,
              topology: topology,
              configuration: configuration,
              dragged: _dragged,
              pictures: _pictures,
              repaint: Listenable.merge([_cachedPositions, extraRepaint]),
            ),
          ),
          layer(
            _EdgesPainter(
              controller: controller,
              topology: topology,
              configuration: configuration,
              dragged: _dragged,
              repaint: Listenable.merge([controller, extraRepaint]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Notifies only when the position of an endpoint of an edge that does not
/// touch a dragged node changed.
class _CachedEdgePositions extends ChangeNotifier {
  GraphController<dynamic, dynamic>? controller;
  late GraphTopology<Object?, Object?> _topology;
  Set<GraphNodeId> _dragged = const {};
  List<double> _signature = const [];
  GraphController<dynamic, dynamic>? _listening;

  void setEdges(
    GraphTopology<Object?, Object?> topology,
    Set<GraphNodeId> dragged,
  ) {
    _topology = topology;
    _dragged = dragged;
    _signature = _read();
    if (!identical(_listening, controller)) {
      _listening?.removeListener(_onChanged);
      _listening = controller?..addListener(_onChanged);
    }
  }

  List<double> _read() {
    final snapshot = controller!.renderSnapshot;
    final result = <double>[];
    for (final edge in _topology.edgesById.values) {
      if (_dragged.contains(edge.sourceId) ||
          _dragged.contains(edge.destinationId)) {
        continue;
      }
      final source = snapshot.resolvePosition(edge.sourceId);
      final destination = snapshot.resolvePosition(edge.destinationId);
      result
        ..add(source?.x ?? double.nan)
        ..add(source?.y ?? double.nan)
        ..add(destination?.x ?? double.nan)
        ..add(destination?.y ?? double.nan);
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

/// One recorded edge, valid while the edge and its endpoints stay put.
class _EdgePicture {
  _EdgePicture(this.edge, this.source, this.destination, this.picture);

  final GraphSceneEdge<Object?> edge;
  final Offset source;
  final Offset destination;
  final ui.Picture picture;
}

/// Recorded pictures of the cached edges, so that a moving resting node
/// re-records only the edges that end at it.
class _EdgePictureCache {
  Object? edgePainter;
  Map<GraphEdgeId, _EdgePicture> entries = {};

  void clear() {
    for (final entry in entries.values) {
      entry.picture.dispose();
    }
    entries = {};
  }

  void dispose() => clear();
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.controller,
    required this.topology,
    required this.configuration,
    required this.dragged,
    required super.repaint,
    this.pictures,
  });

  final GraphController<dynamic, dynamic> controller;
  final GraphTopology<Object?, Object?> topology;
  final GraphViewConfiguration configuration;
  final Set<GraphNodeId> dragged;

  /// Set for the cached layer, which paints the edges that are not incident to
  /// [dragged]; the live layer paints the incident ones.
  final _EdgePictureCache? pictures;

  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = controller.renderSnapshot;
    final cache = pictures;
    final next = <GraphEdgeId, _EdgePicture>{};
    for (final edge in topology.edgesById.values) {
      final incident = dragged.contains(edge.sourceId) ||
          dragged.contains(edge.destinationId);
      if (incident != (cache == null)) {
        continue;
      }
      final sourcePoint = snapshot.resolvePosition(edge.sourceId);
      final destinationPoint = snapshot.resolvePosition(edge.destinationId);
      if (sourcePoint == null || destinationPoint == null) {
        continue;
      }
      final source = Offset(sourcePoint.x, sourcePoint.y);
      final destination = Offset(destinationPoint.x, destinationPoint.y);
      if (cache == null) {
        configuration.edgePainter
            .paint(canvas, edge.payload, source, destination);
        continue;
      }
      var entry = cache.entries.remove(edge.id);
      if (entry == null ||
          entry.edge != edge ||
          entry.source != source ||
          entry.destination != destination) {
        entry?.picture.dispose();
        final recorder = ui.PictureRecorder();
        configuration.edgePainter.paint(
          Canvas(recorder),
          edge.payload,
          source,
          destination,
        );
        entry =
            _EdgePicture(edge, source, destination, recorder.endRecording());
      }
      canvas.drawPicture(entry.picture);
      next[edge.id] = entry;
    }
    if (cache != null) {
      cache
        ..clear()
        ..entries = next;
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) =>
      topology != oldDelegate.topology ||
      configuration.edgePainter != oldDelegate.configuration.edgePainter ||
      !setEquals(dragged, oldDelegate.dragged);
}
