import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

void main() {
  test('HomeTabSpec maps six branches, Me last', () {
    expect(
      [for (final spec in HomeTabSpec.all) (spec.tab, spec.index, spec.path)],
      const [
        (HomeTab.work, 0, '/home/work'),
        (HomeTab.conversations, 1, '/home/conversations'),
        (HomeTab.inbox, 2, '/home/inbox'),
        (HomeTab.constellation, 3, '/home/constellation'),
        (HomeTab.network, 4, '/home/network'),
        (HomeTab.me, 5, '/home/profile'),
      ],
    );
  });

  test('Me is not a destination; destination position equals tab index', () {
    expect(
      [for (final spec in HomeTabSpec.destinations) spec.tab],
      const [
        HomeTab.work,
        HomeTab.conversations,
        HomeTab.inbox,
        HomeTab.constellation,
        HomeTab.network,
      ],
    );
    for (final (i, spec) in HomeTabSpec.destinations.indexed) {
      expect(spec.index, i);
      expect(HomeTabSpec.destinationIndexFor(spec.index), i);
    }
    expect(
      HomeTabSpec.destinationIndexFor(HomeTabSpec.forTab(HomeTab.me).index),
      isNull,
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
      'lib/features/home/ui/widget/home_post_join_listener.dart',
      'lib/features/home/ui/widget/home_rail_frame.dart',
      'lib/features/home/ui/widget/home_account_avatar_button.dart',
      'lib/features/my_work/ui/screen/my_work_screen.dart',
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
