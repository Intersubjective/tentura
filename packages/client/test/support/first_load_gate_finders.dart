import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/ui/widget/first_load_progress.dart';

/// Loading chrome owned by [TenturaFirstLoadGate] (not the hidden child).
int firstLoadGateOverlayCount() => find
    .descendant(
      of: find.byType(TenturaFirstLoadGate),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FirstLoadStatusPanel || widget is TenturaCircularProgress,
      ),
    )
    .evaluate()
    .where((element) {
      var inContent = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TenturaFirstLoadGate) return false;
        if (ancestor.widget is Visibility) inContent = true;
        return true;
      });
      return !inContent;
    })
    .length;
