import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('coordination signal sheet color-codes option labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showCoordinationResponseBottomSheet(
                  context: context,
                  offerUserTitle: 'Helper',
                  initialResponse: null,
                  offerUserAdmittedToRoom: false,
                  onSave:
                      ({
                        required responseTypeSmallint,
                        required inviteToRoom,
                        required removeFromRoom,
                      }) async {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Useful'), findsOneWidget);
    expect(find.text('Need different skill'), findsOneWidget);
    expect(find.text('Need coordination'), findsOneWidget);
    expect(find.text('Not suitable'), findsOneWidget);

    final tt = TenturaTokens.light;
    expect(
      tester.widget<Text>(find.text('Useful')).style?.color,
      coordinationResponseInkColor(tt, CoordinationResponseType.useful),
    );
    expect(
      tester.widget<Text>(find.text('Need different skill')).style?.color,
      coordinationResponseInkColor(
        tt,
        CoordinationResponseType.needDifferentSkill,
      ),
    );
    expect(
      tester.widget<Text>(find.text('Need coordination')).style?.color,
      coordinationResponseInkColor(
        tt,
        CoordinationResponseType.needCoordination,
      ),
    );
    expect(
      tester.widget<Text>(find.text('Not suitable')).style?.color,
      coordinationResponseInkColor(tt, CoordinationResponseType.notSuitable),
    );
    expect(
      coordinationResponseInkColor(
        tt,
        CoordinationResponseType.needDifferentSkill,
      ),
      tt.warn,
    );
  });
}
