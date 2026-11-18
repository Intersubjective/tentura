import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/test_ids.dart';

/// Reveals a lazy picker row before the caller reads its cubit and taps it.
Future<Finder> revealForwardRecipientCheckbox(
  WidgetTester tester,
  String userId, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final checkbox = find.byKey(
    TestIds.key(TestIds.forwardRecipientCheckbox(userId)),
  );
  final scrollable = find.descendant(
    of: find.byType(ForwardRecipientPicker),
    matching: find.byType(Scrollable),
  );
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (checkbox.hitTestable().evaluate().isNotEmpty) return checkbox;
    if (checkbox.evaluate().isNotEmpty) {
      // A cached row is mounted but may be behind pinned search/scope bars.
      // Lay it out in the middle, then re-evaluate after scroll correction.
      await Scrollable.ensureVisible(
        tester.element(checkbox),
        alignment: 0.5,
      );
    } else if (scrollable.evaluate().isNotEmpty) {
      final position = tester.state<ScrollableState>(scrollable.first).position;
      // The NEW header is optional and can itself leave the built range.
      // Scan via the picker, with overlap for rows near a viewport boundary.
      position.jumpTo(
        position.pixels >= position.maxScrollExtent
            ? 0
            : (position.pixels + position.viewportDimension / 2).clamp(
                0,
                position.maxScrollExtent,
              ),
      );
    }
  }
  throw TimeoutException(
    'Recipient checkbox $userId was not revealed',
    timeout,
  );
}
