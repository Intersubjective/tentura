import 'package:meta/meta.dart';

/// Opaque handle for one presentation override generation on a node.
@immutable
final class GraphPresentationToken {
  GraphPresentationToken._(this._owner, this._sequence);

  /// Mints a token; production code should mint only from the scene controller.
  factory GraphPresentationToken.mint({
    required Object owner,
    required int sequence,
  }) =>
      GraphPresentationToken._(owner, sequence);

  final Object _owner;
  final int _sequence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphPresentationToken &&
          identical(_owner, other._owner) &&
          _sequence == other._sequence;

  @override
  int get hashCode => Object.hash(_owner, _sequence);

  @override
  String toString() => 'GraphPresentationToken(seq: $_sequence)';
}
