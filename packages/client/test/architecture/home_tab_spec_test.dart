import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/consts.dart';

void main() {
  test('HomeTabSpec preserves the flagged branch mappings', () {
    expect(
      [for (final spec in HomeTabSpec.all) (spec.tab, spec.index, spec.path)],
      kUpdatesTabEnabled
          ? const [
              (HomeTab.work, 0, '/home/work'),
              (HomeTab.inbox, 1, '/home/inbox'),
              (HomeTab.updates, 2, '/home/updates'),
              (HomeTab.network, 3, '/home/network'),
              (HomeTab.me, 4, '/home/profile'),
            ]
          : const [
              (HomeTab.work, 0, '/home/work'),
              (HomeTab.inbox, 1, '/home/inbox'),
              (HomeTab.network, 2, '/home/network'),
              (HomeTab.me, 3, '/home/profile'),
            ],
    );
  });

  test('home tab consumers do not compare active indexes to literals', () {
    const files = [
      'lib/app/router/home_tab_branches.dart',
      'lib/features/home/ui/screen/home_screen.dart',
      'lib/features/home/ui/widget/home_bottom_nav_listener.dart',
      'lib/features/home/ui/bloc/new_stuff_cubit.dart',
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
