import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
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
  final picker = find.byType(ForwardRecipientPicker);
  final tappableCheckbox = checkbox.hitTestable();
  final scrollView = find.descendant(
    of: picker,
    matching: find.byType(CustomScrollView),
  );
  final elapsed = Stopwatch()..start();
  var searchPending = true;
  await tester.pump();
  while (elapsed.elapsed < timeout) {
    if (tappableCheckbox.evaluate().isNotEmpty) return checkbox;
    if (checkbox.evaluate().firstOrNull case final row?) {
      // A cached row is mounted but may be behind pinned search/scope bars.
      // Lay it out in the middle, then re-evaluate after scroll correction.
      await Scrollable.ensureVisible(row, alignment: 0.5);
    } else {
      final controller = tester
          .widgetList<CustomScrollView>(scrollView)
          .firstOrNull
          ?.controller;
      if (controller == null || !controller.hasClients) {
        await tester.pump(const Duration(milliseconds: 200));
        continue;
      }
      final position = controller.position;
      if (searchPending) {
        searchPending = false;
        if (await _searchForRecipient(tester, picker, userId)
            case final search?) {
          position.jumpTo(position.minScrollExtent);
          await tester.pump();
          if (elapsed.elapsed < timeout &&
              tappableCheckbox.evaluate().isNotEmpty) {
            return checkbox;
          }
          // A result can still sit behind compact search chrome. Restore
          // the original list before continuing with scrolling.
          await tester.enterText(search, '');
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          continue;
        }
      }
      // Adjacent viewports cover every row. A row built under a pinned bar
      // or in the scroll cache is centered by the next iteration.
      position.jumpTo(
        position.pixels >= position.maxScrollExtent
            ? position.minScrollExtent
            : (position.pixels + position.viewportDimension).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
      );
    }
    await tester.pump();
  }
  throw TimeoutException(
    'Recipient checkbox $userId was not revealed',
    timeout,
  );
}

/// Find an unbuilt row through the embedded picker's own search. Candidates
/// outside this list, such as the contextual band, still use the scroll path.
Future<Finder?> _searchForRecipient(
  WidgetTester tester,
  Finder picker,
  String userId,
) async {
  final context = tester.element(picker);
  final hint = L10n.of(context)?.forwardOverlaySearchHint;
  if (hint == null) return null;
  final search = find.descendant(
    of: picker,
    matching: find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    ),
  );
  if (search.evaluate().isEmpty) return null;
  final searchField = tester.widget<TextField>(search);
  if (searchField.controller?.text.isNotEmpty ?? false) return null;
  final candidates = context.read<ForwardCubit>().state.visibleRecipients;
  final candidate = candidates.where((c) => c.id == userId).firstOrNull;
  final name = candidate?.profile.shownName.trim();
  if (name == null || name.isEmpty) return null;
  // Filtering adds pinned chrome on compact pickers. Use it only when it
  // reduces the list.
  if (ForwardState.filterCandidatesByQuery(candidates, name).length ==
      candidates.length) {
    return null;
  }

  await tester.enterText(search, name);
  FocusManager.instance.primaryFocus?.unfocus();
  return search;
}
