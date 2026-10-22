import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engine-visible semantics nodes that say they have input focus.
///
/// On the web the browser's focused element (document.activeElement) is the
/// element of such a node; when Tab moves Flutter's focus to a control whose
/// focus state no node carries, the browser's focus does not move at all and
/// the previous control looks like it takes another Tab press (#415).
/// Requires semantics to be on (`tester.ensureSemantics()`).
List<SemanticsNode> focusedSemanticsNodes() => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().flagsCollection.isFocused == Tristate.isTrue,
    )
    .evaluate()
    .toList();

/// One line naming a semantics node for failure messages.
String describeSemanticsNode(SemanticsNode node) {
  final data = node.getSemanticsData();
  final text = [
    data.label,
    data.tooltip,
  ].where((s) => s.isNotEmpty).join(' / ');
  return '#${node.id} «${text.replaceAll('\n', ' ')}»';
}
