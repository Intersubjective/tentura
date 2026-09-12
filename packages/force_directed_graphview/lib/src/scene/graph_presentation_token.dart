import 'package:meta/meta.dart';

/// Opaque handle for one presentation override generation on a node.
@immutable
final class GraphPresentationToken {
  GraphPresentationToken._(this._owner, this._sequence);

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

/// Mints a presentation token for in-package scene controller and tests only.
///
/// Not exported from the package public entry library; import this library
/// directly only from `lib/src/` or package tests.
@internal
GraphPresentationToken mintGraphPresentationToken({
  required Object owner,
  required int sequence,
}) =>
    GraphPresentationToken._(owner, sequence);
