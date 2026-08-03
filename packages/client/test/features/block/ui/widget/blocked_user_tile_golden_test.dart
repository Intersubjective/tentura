import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/ui/widget/blocked_user_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pumpTile(
  WidgetTester tester, {
  required BlockIntent intent,
  required ThemeData theme,
  required Size logicalSize,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      theme: theme,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: logicalSize),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: logicalSize.width,
                  child: BlockedUserTile(
                    intent: intent,
                    onUnblock: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const logicalSize = Size(360, 120);
  final intent = BlockIntent(
    blocked: const Profile(id: 'blocked-1', displayName: 'Alex Blocked'),
    inheritedCount: 3,
    cascadePending: false,
  );

  testWidgets('BlockedUserTile golden light (C7)', (tester) async {
    await _pumpTile(
      tester,
      intent: intent,
      theme: TenturaTheme.light(),
      logicalSize: logicalSize,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/blocked_user_tile_light.png'),
    );
  });

  testWidgets('BlockedUserTile golden dark (C7)', (tester) async {
    await _pumpTile(
      tester,
      intent: intent,
      theme: TenturaTheme.dark(),
      logicalSize: logicalSize,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/blocked_user_tile_dark.png'),
    );
  });
}
