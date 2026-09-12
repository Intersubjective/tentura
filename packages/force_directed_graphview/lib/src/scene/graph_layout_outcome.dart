import 'package:meta/meta.dart';

import 'package:force_directed_graphview/src/scene/graph_layout_ticket.dart';

/// Latest layout request outcome exposed on [GraphSceneController].
@immutable
sealed class GraphLayoutOutcome {
  const GraphLayoutOutcome();
}

/// No layout request is active and none has completed yet this session.
final class GraphLayoutOutcomeIdle extends GraphLayoutOutcome {
  const GraphLayoutOutcomeIdle();
}

/// A layout stream is in progress for [ticket].
final class GraphLayoutOutcomeRunning extends GraphLayoutOutcome {
  const GraphLayoutOutcomeRunning(this.ticket);

  final GraphLayoutTicket ticket;
}

/// The terminal frame for [ticket] was accepted.
final class GraphLayoutOutcomeSucceeded extends GraphLayoutOutcome {
  const GraphLayoutOutcomeSucceeded(this.ticket);

  final GraphLayoutTicket ticket;
}

/// [ticket] failed before a terminal frame was accepted.
final class GraphLayoutOutcomeFailed extends GraphLayoutOutcome {
  const GraphLayoutOutcomeFailed(
    this.ticket,
    this.error,
    this.stackTrace,
  );

  final GraphLayoutTicket ticket;
  final Object error;
  final StackTrace stackTrace;
}

/// [ticket] was cancelled before completion.
final class GraphLayoutOutcomeCancelled extends GraphLayoutOutcome {
  const GraphLayoutOutcomeCancelled(this.ticket);

  final GraphLayoutTicket ticket;
}
