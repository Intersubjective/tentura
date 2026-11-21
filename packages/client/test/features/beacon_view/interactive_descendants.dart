import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isInteractive(Widget widget) =>
    widget is ButtonStyleButton ||
    widget is IconButton ||
    widget is InkWell ||
    (widget is InkResponse && widget.onTap != null) ||
    (widget is GestureDetector && widget.onTap != null);

Finder findInteractiveDescendants(Finder scope) {
  final roots = scope.evaluate().toSet();
  return find.descendant(
    of: scope,
    matching: find.byElementPredicate((element) {
      if (!_isInteractive(element.widget)) return false;

      // A button can build its own InkWell and gesture detector.
      var insideControl = false;
      element.visitAncestorElements((ancestor) {
        if (roots.contains(ancestor)) return false;
        insideControl = _isInteractive(ancestor.widget);
        return !insideControl;
      });
      return !insideControl;
    }, description: 'interactive widget'),
  );
}
