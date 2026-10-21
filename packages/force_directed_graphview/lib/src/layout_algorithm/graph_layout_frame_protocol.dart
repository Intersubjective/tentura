import 'dart:async';

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
  ///
  /// Once the subscriber cancels, the source is cancelled synchronously and
  /// later frames are dropped unvalidated (an `async*` body would only notice
  /// the cancel at its next `yield`, and validate the late frame first).
  static Stream<GraphLayoutFrame> enforce(
    Stream<GraphLayoutFrame> source,
    GraphLayoutRequest request,
  ) {
    final ingress = GraphLayoutFrameIngress(request);
    late final StreamController<GraphLayoutFrame> controller;
    StreamSubscription<GraphLayoutFrame>? subscription;
    var sawFrame = false;

    void fail(Object error, StackTrace stackTrace) {
      unawaited(subscription?.cancel());
      controller
        ..addError(error, stackTrace)
        ..close();
    }

    controller = StreamController<GraphLayoutFrame>(
      onListen: () {
        subscription = source.listen(
          (frame) {
            try {
              ingress.accept(frame);
            } catch (error, stackTrace) {
              fail(error, stackTrace);
              return;
            }
            sawFrame = true;
            controller.add(frame);
            if (frame.isTerminal) {
              unawaited(subscription?.cancel());
              controller.close();
            }
          },
          onError: fail,
          onDone: () {
            if (!sawFrame || !ingress.terminalReceived) {
              fail(
                GraphLayoutFrameProtocolException(
                  sawFrame
                      ? 'stream closed without terminal frame'
                      : 'stream emitted no frames',
                ),
                StackTrace.current,
              );
            } else {
              controller.close();
            }
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
