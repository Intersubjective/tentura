import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches a [SemanticsNode] or [SemanticsData] whose identifier is exactly
/// [identifier] (what web exposes as `flt-semantics-identifier`).
///
/// flutter_test's `isSemantics(identifier: ...)` and
/// `matchesSemantics(identifier: ...)` accept the argument but never compare
/// it, so an identifier passed there checks nothing (#617). Combine this with
/// `isSemantics` instead: `allOf(isSemantics(...), hasSemanticsIdentifier(id))`.
Matcher hasSemanticsIdentifier(String identifier) =>
    _HasSemanticsIdentifier(identifier);

class _HasSemanticsIdentifier extends CustomMatcher {
  _HasSemanticsIdentifier(String identifier)
    : super('semantics with identifier', 'identifier', equals(identifier));

  @override
  Object? featureValueOf(dynamic actual) => switch (actual) {
    final SemanticsNode node => node.getSemanticsData().identifier,
    final SemanticsData data => data.identifier,
    _ => throw ArgumentError.value(
      actual,
      'actual',
      'expected a SemanticsNode or SemanticsData',
    ),
  };
}
