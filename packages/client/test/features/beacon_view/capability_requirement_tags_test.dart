import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
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
  test('resolveCapabilityRequirementTags skips unknown slugs and sorts', () {
    final tags = resolveCapabilityRequirementTags({
      'money',
      'unknown_slug',
      'transport',
    });
    expect(tags.map((t) => t.slug), ['money', 'transport']);
  });

  testWidgets('renders heading and known capability labels', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CapabilityRequirementTags.fromSlugs(
          slugs: {'money', 'transport'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Looking for:'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('does not use Chip-style Material widgets', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CapabilityRequirementTags.fromSlugs(slugs: {'money'}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Chip), findsNothing);
    expect(find.byType(RawChip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('hides heading when showHeading is false', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CapabilityRequirementTags(
          tags: [CapabilityTag.money],
          showHeading: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Looking for:'), findsNothing);
    expect(find.text('Money'), findsOneWidget);
  });

  testWidgets('tag rows are not interactive Material buttons', (tester) async {
    await tester.pumpWidget(
      _wrap(
        CapabilityRequirementTags.fromSlugs(slugs: {'money'}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('renders nothing when tags are empty', (tester) async {
    await tester.pumpWidget(
      _wrap(const CapabilityRequirementTags(tags: [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Looking for:'), findsNothing);
    expect(find.text('Money'), findsNothing);
  });
}
