import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/ui/bloc/blocked_users_cubit.dart';
import 'package:tentura/features/block/ui/screen/blocked_users_screen.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../../../ui/effect/fake_ui_effect_port.dart';
import '../bloc/blocked_users_cubit_test.dart' show FakeBlockCase;

Future<void> _pumpScreen(
  WidgetTester tester, {
  required BlockedUsersCubit cubit,
  required Size logicalSize,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: logicalSize),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: BlocProvider<BlockedUsersCubit>.value(
              value: cubit,
              child: const BlockedUsersBody(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('BlockedUsersScreen responsive layout (C6)', () {
    late BlockedUsersCubit cubit;

    setUp(() {
      final blocks = [
        BlockIntent(
          blocked: const Profile(id: 'blocked-1', displayName: 'Blocked One'),
          inheritedCount: 2,
          cascadePending: false,
        ),
        BlockIntent(
          blocked: const Profile(id: 'blocked-2', displayName: 'Blocked Two'),
          cascadePending: false,
        ),
      ];
      final case_ = FakeBlockCase()..fetchMyBlocksResult = blocks;
      cubit = BlockedUsersCubit.test(case_: case_, effects: FakeUiEffectPort())
        ..emit(
          BlockedUsersState(
            blocks: blocks,
            status: const StateIsSuccess(),
          ),
        );
    });

    tearDown(() async {
      await cubit.close();
    });

    testWidgets('narrow viewport uses full-width list', (tester) async {
      const logicalSize = Size(400, 800);
      tester.view.physicalSize = logicalSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpScreen(tester, cubit: cubit, logicalSize: logicalSize);

      final listBox = tester.getRect(find.byType(ListView));
      expect(listBox.width, closeTo(logicalSize.width, 1));
    });

    testWidgets('wide viewport constrains list to contentMaxWidth and centers it', (
      tester,
    ) async {
      const logicalSize = Size(1200, 800);
      tester.view.physicalSize = logicalSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpScreen(tester, cubit: cubit, logicalSize: logicalSize);

      final constrained = tester.widget<ConstrainedBox>(
        find.descendant(
          of: find.byType(TenturaContentColumn),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.maxWidth == 720,
          ),
        ),
      );
      expect(constrained.constraints.maxWidth, 720);

      final listBox = tester.getRect(find.byType(ListView));
      expect(listBox.width, closeTo(720, 1));
      expect(listBox.left, closeTo((logicalSize.width - 720) / 2, 1));
    });
  });
}
