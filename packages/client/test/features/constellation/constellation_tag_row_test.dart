import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/person_tag_chip.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _modeToggle = ValueKey('constellation-tag-mode-toggle');

const _neighbour = PersonTag(
  id: 'T1',
  name: 'Neighbour',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _helped = PersonTag(
  id: 'T2',
  name: 'Helped me',
  glyph: 'H',
  color: 1,
  ord: 1,
);

Future<void> _pump(
  WidgetTester tester, {
  List<PersonTag> ownTags = const [],
  ConstellationTagFilter filter = const ConstellationTagFilter(),
  ValueChanged<String>? onToggleOwn,
  ValueChanged<ConstellationTagFilterMode>? onModeChanged,
  VoidCallback? onAddTag,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: ConstellationTagRow(
        ownTags: ownTags,
        autoTags: const [],
        filter: filter,
        onToggleOwn: onToggleOwn ?? (_) {},
        onToggleAuto: (_) {},
        onModeChanged: onModeChanged ?? (_) {},
        onAddTag: onAddTag ?? () {},
      ),
    ),
  ),
);

void main() {
  group('ConstellationTagRow', () {
    testWidgets('without own tags row 1 is a single "+ Tag"', (tester) async {
      var added = 0;
      await _pump(tester, onAddTag: () => added++);

      expect(find.text('+ Tag'), findsOneWidget);
      expect(find.byType(PersonTagChip), findsNothing);
      expect(find.textContaining('More'), findsNothing);
      // No counters of any kind: not a "More N", not a per-tag count.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'\d').hasMatch(w.data ?? ''),
        ),
        findsNothing,
      );
      expect(find.byKey(_modeToggle), findsNothing);

      await tester.tap(find.text('+ Tag'));
      expect(added, 1);
    });

    testWidgets('own tags show as chips and tapping one toggles it', (
      tester,
    ) async {
      final toggled = <String>[];
      await _pump(
        tester,
        ownTags: const [_neighbour, _helped],
        onToggleOwn: toggled.add,
      );

      expect(find.byType(PersonTagChip), findsNWidgets(2));
      expect(find.text('+ Tag'), findsNothing);

      await tester.tap(find.text('Helped me'));
      expect(toggled, ['T2']);
    });

    testWidgets('the and/or switch appears only with two tags selected', (
      tester,
    ) async {
      await _pump(
        tester,
        ownTags: const [_neighbour, _helped],
        filter: const ConstellationTagFilter(selectedOwn: {'T1'}),
      );
      expect(find.byKey(_modeToggle), findsNothing);

      await _pump(
        tester,
        ownTags: const [_neighbour, _helped],
        filter: const ConstellationTagFilter(selectedOwn: {'T1', 'T2'}),
      );
      expect(find.byKey(_modeToggle), findsOneWidget);
    });

    testWidgets('the switch asks for "and" when the filter is on "or"', (
      tester,
    ) async {
      final modes = <ConstellationTagFilterMode>[];
      await _pump(
        tester,
        ownTags: const [_neighbour, _helped],
        filter: const ConstellationTagFilter(selectedOwn: {'T1', 'T2'}),
        onModeChanged: modes.add,
      );

      await tester.tap(find.byKey(_modeToggle));

      expect(modes, [ConstellationTagFilterMode.and]);
    });
  });
}
