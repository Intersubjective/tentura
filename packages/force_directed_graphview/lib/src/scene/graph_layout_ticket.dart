import 'package:meta/meta.dart';

/// Identifies one layout request within a controller session.
///
/// Equality includes the opaque controller owner so tickets from different
/// controllers never match.
@immutable
final class GraphLayoutTicket {
  GraphLayoutTicket._(this._owner, this.topologyRevision, this.generation);

  /// Mints a ticket; production code should mint only from the scene controller.
  factory GraphLayoutTicket.mint({
    required Object owner,
    required int topologyRevision,
    required int generation,
  }) =>
      GraphLayoutTicket._(owner, topologyRevision, generation);

  final Object _owner;
  final int topologyRevision;
  final int generation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphLayoutTicket &&
          identical(_owner, other._owner) &&
          topologyRevision == other.topologyRevision &&
          generation == other.generation;

  @override
  int get hashCode => Object.hash(_owner, topologyRevision, generation);

  @override
  String toString() =>
      'GraphLayoutTicket(rev: $topologyRevision, gen: $generation)';
}
