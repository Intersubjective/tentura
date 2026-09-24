import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'fixtures/constellation_reference_fixture.dart';

void main() {
  group('ConstellationOverflowGroup', () {
    testWidgets('chip size matches constellationOverflowChipSize helper',
        (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 400)),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: const ConstellationOverflowGroup(
                  authorId: 'ego',
                  authorName: 'Vadim',
                  hiddenCount: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chip = find.byWidgetPredicate(
        (widget) =>
            widget is SizedBox &&
            widget.key == const Key('constellation.overflow.ego'),
      );
      expect(chip, findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(chip);
      final chipContext = tester.element(chip);
      final expected = constellationOverflowChipSize(
        chipContext,
        L10n.of(chipContext)!.constellationMoreRequests(3),
      );
      expect(sizedBox.width, closeTo(expected.width, 0.5));
      expect(sizedBox.height, closeTo(expected.height, 0.5));
    });

    testWidgets('expanded state shows fewer label and semantics', (tester) async {
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 400)),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: const ConstellationOverflowGroup(
                  authorId: 'ego',
                  authorName: 'Vadim',
                  hiddenCount: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('constellation.overflow.ego')));
      await tester.pumpAndSettle();
      expect(cubit.isSatelliteOverflowExpanded('ego'), isTrue);
      expect(find.text('Show fewer'), findsOneWidget);
      final semantics = tester.getSemantics(find.byKey(
        const Key('constellation.overflow.ego'),
      ));
      expect(semantics.label, contains('Show fewer'));
      expect(semantics.label, contains('Vadim'));
    });
  });
}
