// SPDX-License-Identifier: AGPL-3.0-only
// Issue #488 (owner review on PR #610): the complaint link carries only the
// reported id. The form fetches the title/author itself, so a crafted
// `?title=…&author=…` cannot mislabel the item and private Request titles stay
// out of the URL bar, history and logs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../effect/fake_ui_effect_port.dart';

const _complaintCallers = [
  'lib/features/beacon_view/ui/widget/beacon_view_app_bar_overflow.dart',
  'lib/features/inbox/ui/widget/inbox_watchlist_row.dart',
  'lib/features/my_work/ui/widget/my_work_cards.dart',
  'lib/features/post_view/ui/screen/post_view_screen.dart',
  'lib/features/profile_view/ui/widget/profile_view_app_bar.dart',
];

/// Argument lists of every `showComplaint(...)` call in [source].
List<String> _showComplaintArgs(String source) {
  const call = 'showComplaint(';
  final args = <String>[];
  var start = source.indexOf(call);
  while (start >= 0) {
    final open = start + call.length;
    var depth = 1;
    var i = open;
    while (i < source.length && depth > 0) {
      final ch = source[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      i++;
    }
    args.add(source.substring(open, i - 1));
    start = source.indexOf(call, i);
  }
  return args;
}

void main() {
  test('showComplaint pushes the bare complaint path, no query', () {
    final effects = FakeUiEffectPort();
    ScreenCubit(effects).showComplaint('B1');

    final push = effects.emitted.whereType<NavigatePush>().single;
    final uri = Uri.parse(push.path);
    expect(uri.path, '$kPathComplaint/B1');
    expect(uri.query, isEmpty);
    expect(push.path, '$kPathComplaint/B1');
  });

  test('showComplaint takes no title or author', () {
    final source = File('lib/ui/bloc/screen_cubit.dart').readAsStringSync();
    final start = source.indexOf('void showComplaint(');
    expect(start, isNonNegative);
    final signature = source.substring(start, source.indexOf(')', start));

    expect(signature, isNot(contains('title')));
    expect(signature, isNot(contains('author')));
  });

  test('no complaint entry point puts a title or author in the link', () {
    for (final path in _complaintCallers) {
      final calls = _showComplaintArgs(File(path).readAsStringSync());
      expect(calls, isNotEmpty, reason: '$path no longer opens a complaint');
      for (final args in calls) {
        expect(
          args,
          isNot(contains('title:')),
          reason: '$path: showComplaint($args)',
        );
        expect(
          args,
          isNot(contains('author:')),
          reason: '$path: showComplaint($args)',
        );
      }
    }
  });
}
