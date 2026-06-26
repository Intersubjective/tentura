import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/capability/ui/widget/removable_capability_chips.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('renders removable chips for known slugs', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemovableCapabilityChips(
          slugs: {'money', 'transport'},
          onRemove: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2));
  });

  testWidgets('onRemove fires with slug when delete is tapped', (tester) async {
    String? removed;
    await tester.pumpWidget(
      _wrap(
        RemovableCapabilityChips(
          slugs: {'money', 'transport'},
          onRemove: (slug) => removed = slug,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final moneyChip = find.ancestor(
      of: find.text('Money'),
      matching: find.byType(InputChip),
    );
    await tester.tap(
      find.descendant(
        of: moneyChip,
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pumpAndSettle();

    expect(removed, 'money');
  });

  testWidgets('renders nothing when slugs are empty', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemovableCapabilityChips(
          slugs: const {},
          onRemove: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
  });
}
