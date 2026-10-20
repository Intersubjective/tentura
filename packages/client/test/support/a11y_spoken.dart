import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a screen reader is handed for one engine-visible semantics node:
/// label, value and tooltip. Flutter web joins label and tooltip into one
/// aria-label, so a tooltip that repeats the label is announced twice (#416).
String spokenTextOf(SemanticsNode node) {
  final data = node.getSemanticsData();
  return [
    data.label,
    data.value,
    data.tooltip,
  ].where((part) => part.isNotEmpty).join('\n');
}

/// Spoken text of every node the engine sees (nodes merged into a parent are
/// counted once, through that parent).
List<String> spokenNodes() => find.semantics
    .byPredicate((node) => !node.isMergedIntoParent)
    .evaluate()
    .map(spokenTextOf)
    .where((text) => text.isNotEmpty)
    .toList();

/// How many times [phrase] is announced across the whole semantics tree.
int spokenCount(String phrase) => spokenNodes().fold(
  0,
  (sum, text) => sum + phrase.allMatches(text).length,
);

/// Every announced line (label, value and tooltip split on newlines).
List<String> spokenLines() =>
    spokenNodes().expand((text) => text.split('\n')).toList();
