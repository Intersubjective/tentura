import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_request.dart';
import 'package:force_directed_graphview/src/layout_algorithm/scene_layout_algorithm.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';

/// Layout stream violated the ticketed frame protocol.
final class GraphLayoutFrameProtocolException implements Exception {
  GraphLayoutFrameProtocolException(this.message);

  final String message;

  @override
  String toString() => 'GraphLayoutFrameProtocolException: $message';
}

/// Result of validating one [GraphLayoutFrame] against an active request.
enum GraphLayoutFrameDisposition {
  accepted,
  staleTicket,
  duplicateOrBackwardSequence,
  postTerminal,
  partialOrExtraPositions,
  nonFinitePosition,
}

/// Validates frames for a single [GraphLayoutRequest] without controller state.
///
/// The scene controller (M03) owns ticket lifecycle; this type only tracks
/// sequence and terminal completion for one stream subscription.
final class GraphLayoutFrameIngress {
  GraphLayoutFrameIngress(this.request)
      : _expectedNodeIds = request.nodeIds,
        _expectedTicket = request.ticket;

  final GraphLayoutRequest request;
  final Set<GraphNodeId> _expectedNodeIds;
  final GraphLayoutTicket _expectedTicket;

  int _lastSequence = -1;
  bool _terminalReceived = false;

  bool get terminalReceived => _terminalReceived;

  /// Classifies [frame] without mutating ingress state when rejected.
  GraphLayoutFrameDisposition classify(GraphLayoutFrame frame) {
    if (_terminalReceived) {
      return GraphLayoutFrameDisposition.postTerminal;
    }
    if (frame.ticket != _expectedTicket) {
      return GraphLayoutFrameDisposition.staleTicket;
    }
    if (frame.sequence <= _lastSequence) {
      return GraphLayoutFrameDisposition.duplicateOrBackwardSequence;
    }
    if (frame.positions.length != _expectedNodeIds.length) {
      return GraphLayoutFrameDisposition.partialOrExtraPositions;
    }
    for (final id in _expectedNodeIds) {
      if (!frame.positions.containsKey(id)) {
        return GraphLayoutFrameDisposition.partialOrExtraPositions;
      }
    }
    for (final point in frame.positions.values) {
      if (!point.x.isFinite || !point.y.isFinite) {
        return GraphLayoutFrameDisposition.nonFinitePosition;
      }
    }
    return GraphLayoutFrameDisposition.accepted;
  }

  /// Records an [accepted] frame; throws [GraphLayoutFrameProtocolException]
  /// for any other disposition.
  void accept(GraphLayoutFrame frame) {
    final disposition = classify(frame);
    if (disposition != GraphLayoutFrameDisposition.accepted) {
      throw GraphLayoutFrameProtocolException(disposition.name);
    }
    _lastSequence = frame.sequence;
    if (frame.isTerminal) {
      _terminalReceived = true;
    }
  }

  /// Yields only accepted frames; fails the stream on rejection or if the
  /// source completes without a terminal frame.
  static Stream<GraphLayoutFrame> enforce(
    Stream<GraphLayoutFrame> source,
    GraphLayoutRequest request,
  ) async* {
    final ingress = GraphLayoutFrameIngress(request);
    var sawFrame = false;
    await for (final frame in source) {
      ingress.accept(frame);
      sawFrame = true;
      yield frame;
      if (frame.isTerminal) {
        return;
      }
    }
    if (!sawFrame || !ingress.terminalReceived) {
      throw GraphLayoutFrameProtocolException(
        sawFrame ? 'stream closed without terminal frame' : 'stream emitted no frames',
      );
    }
  }
}
