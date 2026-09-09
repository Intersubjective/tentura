import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

void main() {
  test('HomeTabSpec preserves the five-tab branch mappings after UNIT 14', () {
    expect(
      [for (final spec in HomeTabSpec.all) (spec.tab, spec.index, spec.path)],
      const [
        (HomeTab.work, 0, '/home/work'),
        (HomeTab.inbox, 1, '/home/inbox'),
        (HomeTab.constellation, 2, '/home/constellation'),
        (HomeTab.network, 3, '/home/network'),
        (HomeTab.me, 4, '/home/profile'),
      ],
    );
  });

  test('folded Updates tab alias resolves to Inbox branch index', () {
    expect(
      HomeTabSpec.forTab(HomeTab.updates).tab,
      HomeTab.inbox,
    );
    expect(
      HomeTabSpec.forTab(HomeTab.updates).index,
      HomeTabSpec.forTab(HomeTab.inbox).index,
    );
  });

  test('home tab consumers do not compare active indexes to literals', () {
    const files = [
      'lib/app/router/home_tab_branches.dart',
      'lib/features/home/ui/screen/home_screen.dart',
      'lib/features/home/ui/widget/home_bottom_nav_listener.dart',
      'lib/features/home/ui/bloc/home_attention_cubit.dart',
      'lib/features/inbox/ui/screen/inbox_screen.dart',
    ];
    final positionalComparison = RegExp(
      r'(active(Index|HomeTabIndex)|setActiveIndex)\s*[=!<>]=?\s*\d+',
    );

    for (final path in files) {
      expect(
        positionalComparison.hasMatch(File(path).readAsStringSync()),
        isFalse,
        reason: path,
      );
    }
  });
}
