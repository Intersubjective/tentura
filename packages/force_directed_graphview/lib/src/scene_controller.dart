import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_frame_protocol.dart';
import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_request.dart';
import 'package:force_directed_graphview/src/layout_algorithm/scene_layout_algorithm.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_outcome.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart'
    show GraphLayoutTicket, mintGraphLayoutTicket;
import 'package:force_directed_graphview/src/scene/graph_presentation_token.dart'
    show GraphPresentationToken, mintGraphPresentationToken;
import 'package:force_directed_graphview/src/scene/graph_topology.dart';
import 'package:force_directed_graphview/src/scene/scene_geometry.dart';
import 'package:force_directed_graphview/src/scene/scene_layout.dart';
import 'package:force_directed_graphview/src/scene/scene_presentation.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/scene/scene_transition.dart';

/// ID-keyed scene session state: topology, layout, and presentation.
///
/// Camera and Flutter view binding stay outside this type until M04/M05.
class GraphSceneController<N, E> with ChangeNotifier {
  GraphSceneController()
      : _topology = GraphTopology<N, E>.fromEntries(
          nodes: const [],
          edges: const [],
        );

  GraphTopology<N, E> _topology;
  var _topologyRevision = 0;
  SceneLayout? _layout;
  var _layoutRevision = 0;
  ScenePresentation _presentation = ScenePresentation();
  SceneTransition? _transition;
  Map<GraphNodeId, ScenePoint> _seedPositions = {};
  GraphLayoutOutcome _layoutOutcome = const GraphLayoutOutcomeIdle();

  GraphLayoutTicket? _activeTicket;
  StreamSubscription<GraphLayoutFrame>? _layoutSubscription;
  var _layoutRequestGeneration = 0;
  var _presentationTokenSequence = 0;

  final Map<GraphPresentationToken, GraphNodeId> _tokenNodes = {};
  final Map<GraphNodeId, GraphPresentationToken> _activePresentationTokenByNode =
      {};

  var _disposed = false;
  var _notifying = false;

  GraphLayoutOutcome get layoutOutcome => _layoutOutcome;

  int get topologyRevision => _topologyRevision;

  GraphSceneSnapshot<N, E> get snapshot => GraphSceneSnapshot<N, E>(
        topology: _topology,
        layout: _layout,
        presentation: _presentation,
        transition: _transition,
        seedPositions: _seedPositions,
      );

  /// Validates and publishes [next] in one atomic snapshot update.
  ///
  /// Does not request layout; call [requestLayout] explicitly when needed.
  void applyTopology(
    GraphTopology<N, E> next, {
    Map<GraphNodeId, ScenePoint> initialPositions = const {},
  }) {
    _assertLive();
    _assertNotNotifying();

    for (final entry in initialPositions.entries) {
      assertNonEmptyGraphId(entry.key, 'initialPositions key');
      if (!next.nodesById.containsKey(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'initialPositions',
          'unknown node id',
        );
      }
    }

    final previousIds = _topology.nodesById.keys.toSet();
    final nextIds = next.nodesById.keys.toSet();
    final addedIds = nextIds.difference(previousIds);
    for (final id in addedIds) {
      final hasLayout = _layout?.positions.containsKey(id) ?? false;
      if (!hasLayout &&
          !initialPositions.containsKey(id) &&
          _layout != null) {
        throw ArgumentError(
          'initialPositions must supply a finite position for added node $id',
        );
      }
    }

    final layoutAffecting = _isLayoutAffecting(_topology, next);

    if (!layoutAffecting) {
      _topology = next;
      _commit();
      return;
    }

    _invalidateActiveLayoutTicket();

    SceneLayout? nextLayout = _layout;
    if (nextIds.isEmpty) {
      nextLayout = null;
    } else if (nextLayout != null) {
      final filtered = <GraphNodeId, ScenePoint>{};
      for (final id in nextIds) {
        final point = nextLayout.positions[id];
        if (point != null) {
          filtered[id] = point;
        }
      }
      nextLayout = filtered.isEmpty
          ? null
          : SceneLayout(
              ticket: nextLayout.ticket,
              revision: nextLayout.revision,
              positions: filtered,
            );
    }
    _topologyRevision++;

    final removedIds = previousIds.difference(nextIds);
    _topology = next;
    _layout = nextLayout;

    final overrides = Map<GraphNodeId, ScenePoint>.from(_presentation.overrides);
    final holds =
        Map<GraphNodeId, GraphPresentationHold>.from(_presentation.holds);
    final paintOrder = List<GraphNodeId>.from(_presentation.paintOrder);

    for (final id in removedIds) {
      overrides.remove(id);
      holds.remove(id);
      paintOrder.remove(id);
      _seedPositions.remove(id);
      final token = _activePresentationTokenByNode.remove(id);
      if (token != null) {
        _tokenNodes.remove(token);
      }
    }

    final seeds = Map<GraphNodeId, ScenePoint>.from(_seedPositions);
    for (final id in addedIds) {
      final initial = initialPositions[id];
      if (initial != null) {
        seeds[id] = initial;
      }
    }
    for (final id in nextIds) {
      if (_layout?.positions.containsKey(id) ?? false) {
        seeds.remove(id);
      }
    }
    _seedPositions = seeds;

    _presentation = ScenePresentation(
      overrides: overrides,
      paintOrder: paintOrder,
      holds: holds,
    );

    _commit();
  }

  GraphPresentationToken beginPresentation(
    GraphNodeId id,
    ScenePoint position,
  ) {
    _assertLive();
    _assertNotNotifying();
    assertNonEmptyGraphId(id, 'id');
    if (!_topology.nodesById.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'unknown node');
    }

    final token = mintGraphPresentationToken(
      owner: this,
      sequence: ++_presentationTokenSequence,
    );
    _tokenNodes[token] = id;
    _activePresentationTokenByNode[id] = token;

    final overrides = Map<GraphNodeId, ScenePoint>.from(_presentation.overrides)
      ..[id] = position;
    _presentation = ScenePresentation(
      overrides: overrides,
      paintOrder: _presentation.paintOrder,
      holds: _presentation.holds,
    );
    _transition = null;
    _commit();
    return token;
  }

  bool updatePresentation(
    GraphPresentationToken token,
    ScenePoint position,
  ) {
    _assertLive();
    _assertNotNotifying();
    final nodeId = _tokenNodes[token];
    if (nodeId == null) {
      return false;
    }
    if (_activePresentationTokenByNode[nodeId] != token) {
      return false;
    }
    if (!_topology.nodesById.containsKey(nodeId)) {
      return false;
    }

    final overrides = Map<GraphNodeId, ScenePoint>.from(_presentation.overrides)
      ..[nodeId] = position;
    _presentation = ScenePresentation(
      overrides: overrides,
      paintOrder: _presentation.paintOrder,
      holds: _presentation.holds,
    );
    _commit();
    return true;
  }

  /// Removes every presentation override and hold.
  void clearAllPresentationOverrides() {
    _assertLive();
    _assertNotNotifying();
    if (_presentation.overrides.isEmpty && _presentation.holds.isEmpty) {
      return;
    }
    _tokenNodes.clear();
    _activePresentationTokenByNode.clear();
    _presentation = ScenePresentation(paintOrder: _presentation.paintOrder);
    _transition = null;
    _commit();
  }

  /// Cancels the active presentation override for [id], if any.
  bool clearPresentationForNode(GraphNodeId id) {
    final token = _activePresentationTokenByNode[id];
    if (token == null) {
      return false;
    }
    return cancelPresentation(token);
  }

  bool cancelPresentation(GraphPresentationToken token) {
    _assertLive();
    _assertNotNotifying();
    final nodeId = _tokenNodes[token];
    if (nodeId == null) {
      return false;
    }
    if (_activePresentationTokenByNode[nodeId] != token) {
      return false;
    }

    _activePresentationTokenByNode.remove(nodeId);
    _tokenNodes.remove(token);

    final overrides = Map<GraphNodeId, ScenePoint>.from(_presentation.overrides);
    overrides.remove(nodeId);
    final holds =
        Map<GraphNodeId, GraphPresentationHold>.from(_presentation.holds);
    holds.remove(nodeId);

    _presentation = ScenePresentation(
      overrides: overrides,
      paintOrder: _presentation.paintOrder,
      holds: holds,
    );
    _commit();
    return true;
  }

  GraphLayoutTicket requestLayout(
    SceneLayoutAlgorithm algorithm, {
    required SceneSize canvasSize,
    Set<GraphPresentationToken> releaseOnTerminal = const {},
  }) {
    _assertLive();
    _assertNotNotifying();

    _invalidateActiveLayoutTicket();

    final generation = ++_layoutRequestGeneration;
    final ticket = mintGraphLayoutTicket(
      owner: this,
      topologyRevision: _topologyRevision,
      generation: generation,
    );
    _activeTicket = ticket;

    final holds =
        Map<GraphNodeId, GraphPresentationHold>.from(_presentation.holds);
    for (final token in releaseOnTerminal) {
      final nodeId = _tokenNodes[token];
      if (nodeId == null) {
        continue;
      }
      if (!_topology.nodesById.containsKey(nodeId)) {
        continue;
      }
      if (_activePresentationTokenByNode[nodeId] != token) {
        continue;
      }
      holds[nodeId] = GraphPresentationHold(token: token, ticket: ticket);
    }
    _presentation = ScenePresentation(
      overrides: _presentation.overrides,
      paintOrder: _presentation.paintOrder,
      holds: holds,
    );

    final request = _buildLayoutRequest(ticket, canvasSize);
    _layoutOutcome = GraphLayoutOutcomeRunning(ticket);

    final stream = GraphLayoutFrameIngress.enforce(
      algorithm.layout(request),
      request,
    );

    _layoutSubscription = stream.listen(
      (frame) => _onLayoutFrame(ticket, frame, releaseOnTerminal),
      onError: (Object error, StackTrace stackTrace) {
        _failLayout(ticket, error, stackTrace);
      },
      onDone: () {
        if (_activeTicket == ticket &&
            _layoutOutcome is GraphLayoutOutcomeRunning) {
          _failLayout(
            ticket,
            GraphLayoutFrameProtocolException(
              'stream closed without terminal frame',
            ),
            StackTrace.current,
          );
        }
      },
      cancelOnError: true,
    );

    _commit();
    return ticket;
  }

  bool cancelLayout(GraphLayoutTicket ticket) {
    _assertLive();
    if (_activeTicket != ticket) {
      return false;
    }
    _invalidateActiveLayoutTicket(outcome: GraphLayoutOutcomeCancelled(ticket));
    _commit();
    return true;
  }

  ScenePoint? resolvePosition(GraphNodeId id) => snapshot.resolvePosition(id);

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _layoutSubscription?.cancel();
    _layoutSubscription = null;
    _activeTicket = null;
    _tokenNodes.clear();
    _activePresentationTokenByNode.clear();
    super.dispose();
  }

  void _onLayoutFrame(
    GraphLayoutTicket ticket,
    GraphLayoutFrame frame,
    Set<GraphPresentationToken> releaseOnTerminal,
  ) {
    if (_disposed || _activeTicket != ticket) {
      return;
    }

    if (frame.isTerminal) {
      _acceptTerminalLayout(frame, releaseOnTerminal);
      _activeTicket = null;
      _layoutSubscription = null;
    } else {
      _layoutRevision++;
      _layout = SceneLayout(
        ticket: frame.ticket,
        revision: _layoutRevision,
        positions: frame.positions,
      );
      _clearSeedsCoveredBy(frame.positions);
      _layoutOutcome = GraphLayoutOutcomeRunning(ticket);
      _commit();
    }
  }

  void _acceptTerminalLayout(
    GraphLayoutFrame frame,
    Set<GraphPresentationToken> releaseOnTerminal,
  ) {
    _layoutRevision++;
    _layout = SceneLayout(
      ticket: frame.ticket,
      revision: _layoutRevision,
      positions: frame.positions,
    );
    _clearSeedsCoveredBy(frame.positions);

    final overrides =
        Map<GraphNodeId, ScenePoint>.from(_presentation.overrides);
    final holds =
        Map<GraphNodeId, GraphPresentationHold>.from(_presentation.holds);
    final release = releaseOnTerminal.toSet();

    for (final token in release) {
      final nodeId = _tokenNodes[token];
      if (nodeId == null) {
        continue;
      }
      final hold = holds[nodeId];
      if (hold?.ticket == frame.ticket && hold?.token == token) {
        overrides.remove(nodeId);
        holds.remove(nodeId);
      }
    }

    _presentation = ScenePresentation(
      overrides: overrides,
      paintOrder: _presentation.paintOrder,
      holds: holds,
    );
    _transition = null;
    _layoutOutcome = GraphLayoutOutcomeSucceeded(frame.ticket);
    _commit();
  }

  void _failLayout(
    GraphLayoutTicket ticket,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_disposed || _activeTicket != ticket) {
      return;
    }
    _activeTicket = null;
    _layoutSubscription?.cancel();
    _layoutSubscription = null;
    _layoutOutcome = GraphLayoutOutcomeFailed(ticket, error, stackTrace);
    _commit();
  }

  void _invalidateActiveLayoutTicket({
    GraphLayoutOutcome? outcome,
  }) {
    final ticket = _activeTicket;
    if (ticket == null) {
      return;
    }
    _activeTicket = null;
    _layoutSubscription?.cancel();
    _layoutSubscription = null;
    if (_layoutOutcome is GraphLayoutOutcomeRunning &&
        _layout?.ticket == ticket) {
      _layout = null;
    }
    if (outcome != null) {
      _layoutOutcome = outcome;
    } else if (_layoutOutcome is GraphLayoutOutcomeRunning) {
      _layoutOutcome = GraphLayoutOutcomeCancelled(ticket);
    }
  }

  GraphLayoutRequest _buildLayoutRequest(
    GraphLayoutTicket ticket,
    SceneSize canvasSize,
  ) {
    final nodesById = <GraphNodeId, GraphLayoutNode>{};
    for (final entry in _topology.nodesById.entries) {
      final node = entry.value;
      nodesById[entry.key] = GraphLayoutNode(
        id: entry.key,
        size: node.size,
        simulationFixed: node.simulationFixed,
      );
    }
    final edgesById = <GraphEdgeId, GraphLayoutEdge>{};
    for (final entry in _topology.edgesById.entries) {
      final edge = entry.value;
      edgesById[entry.key] = GraphLayoutEdge(
        id: entry.key,
        sourceId: edge.sourceId,
        destinationId: edge.destinationId,
      );
    }

    SceneLayout? previous;
    final layout = _layout;
    if (layout != null) {
      final filtered = <GraphNodeId, ScenePoint>{};
      for (final id in _topology.nodesById.keys) {
        final point = layout.positions[id];
        if (point != null) {
          filtered[id] = point;
        }
      }
      if (filtered.isNotEmpty) {
        previous = SceneLayout(
          ticket: layout.ticket,
          revision: layout.revision,
          positions: filtered,
        );
      }
    }

    return GraphLayoutRequest(
      ticket: ticket,
      canvasSize: canvasSize,
      nodesById: nodesById,
      edgesById: edgesById,
      previous: previous,
    );
  }

  bool _isLayoutAffecting(
    GraphTopology<N, E> current,
    GraphTopology<N, E> next,
  ) {
    if (current.nodesById.keys.length != next.nodesById.keys.length) {
      return true;
    }
    if (current.edgesById.keys.length != next.edgesById.keys.length) {
      return true;
    }
    for (final id in current.nodesById.keys) {
      if (!next.nodesById.containsKey(id)) {
        return true;
      }
      final left = current.nodesById[id]!;
      final right = next.nodesById[id]!;
      if (left.size != right.size || left.simulationFixed != right.simulationFixed) {
        return true;
      }
    }
    for (final id in current.edgesById.keys) {
      if (!next.edgesById.containsKey(id)) {
        return true;
      }
      final left = current.edgesById[id]!;
      final right = next.edgesById[id]!;
      if (left.sourceId != right.sourceId ||
          left.destinationId != right.destinationId) {
        return true;
      }
    }
    return false;
  }

  void _clearSeedsCoveredBy(Map<GraphNodeId, ScenePoint> positions) {
    if (_seedPositions.isEmpty) {
      return;
    }
    _seedPositions = Map<GraphNodeId, ScenePoint>.from(_seedPositions)
      ..removeWhere((id, _) => positions.containsKey(id));
  }

  void _commit() {
    if (_disposed) {
      return;
    }
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
    }
  }

  void _assertLive() {
    if (_disposed) {
      throw StateError('GraphSceneController is disposed');
    }
  }

  void _assertNotNotifying() {
    if (_notifying) {
      throw StateError('Cannot mutate scene state during notification');
    }
  }
}
