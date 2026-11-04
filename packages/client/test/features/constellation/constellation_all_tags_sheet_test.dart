import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

const _longRuName = 'Соседи по даче в Подмосковье';
const _sheetScrollKey = Key('constellation-all-tags-sheet-scroll');

List<PersonTag> _manyRuTags(int count) => [
  for (var i = 0; i < count; i++)
    PersonTag(
      id: 'tag-$i',
      name: '$_longRuName $i',
      glyph: '${i % 10}',
      color: i % 8,
      ord: i,
    ),
];

Future<void> _openSheet(
  WidgetTester tester, {
  required ConstellationTagLensCubit lens,
  required List<PersonTag> ownTags,
  required Size surface,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider.value(
        value: lens,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-all-tags-sheet'),
              onPressed: () => showConstellationAllTagsSheet(
                context: context,
                lensCubit: lens,
                ownTags: ownTags,
                autoTags: const [],
                onAddTag: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-all-tags-sheet')));
  await tester.pumpAndSettle();
}

Finder _sheetScrollable() => find.descendant(
  of: find.byKey(_sheetScrollKey),
  matching: find.byType(Scrollable),
);

double _sheetScrollOffset(WidgetTester tester) {
  return tester.state<ScrollableState>(_sheetScrollable()).position.pixels;
}

Finder _sheetWrap() => find.descendant(
  of: find.byKey(_sheetScrollKey),
  matching: find.byType(Wrap),
);

void main() {
  group('All tags sheet', () {
    testWidgets('375×667 RU: chip tap does not jump sheet scroll', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final lens = ConstellationTagLensCubit();
      addTearDown(lens.close);
      await _openSheet(
        tester,
        lens: lens,
        ownTags: _manyRuTags(30),
        surface: kPhoneSurface,
      );
      await tester.drag(_sheetScrollable(), const Offset(0, -280));
      await tester.pumpAndSettle();
      final before = _sheetScrollOffset(tester);
      expect(before, greaterThan(40));
      await tester.tap(find.text('$_longRuName 15'));
      await tester.pumpAndSettle();
      expect(_sheetScrollOffset(tester), before);
    });

    testWidgets('360×640 RU: chip tap does not jump sheet scroll', (
      tester,
    ) async {
      const surface = Size(360, 640);
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final lens = ConstellationTagLensCubit();
      addTearDown(lens.close);
      await _openSheet(
        tester,
        lens: lens,
        ownTags: _manyRuTags(30),
        surface: surface,
      );
      await tester.drag(_sheetScrollable(), const Offset(0, -240));
      await tester.pumpAndSettle();
      final before = _sheetScrollOffset(tester);
      await tester.tap(find.text('$_longRuName 8'));
      await tester.pumpAndSettle();
      expect(_sheetScrollOffset(tester), before);
    });

    testWidgets('two selected chips show outline and Любой из них in sheet', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final lens = ConstellationTagLensCubit();
      addTearDown(lens.close);
      await _openSheet(
        tester,
        lens: lens,
        ownTags: _manyRuTags(8),
        surface: kPhoneSurface,
      );
      await tester.tap(find.text('$_longRuName 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$_longRuName 1'));
      await tester.pumpAndSettle();
      expect(find.text('Любой из них'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
        findsAtLeast(2),
      );
      expect(lens.state.selectedOwn, containsAll(['tag-0', 'tag-1']));
    });

    testWidgets('wrap layout has no scroll-row gap SizedBox spacers', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final lens = ConstellationTagLensCubit();
      addTearDown(lens.close);
      await _openSheet(
        tester,
        lens: lens,
        ownTags: _manyRuTags(30),
        surface: kPhoneSurface,
      );
      final gapWidth =
          TenturaTheme.light().extension<TenturaTokens>()!.iconTextGap * 2;
      expect(
        find.descendant(
          of: _sheetWrap(),
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == gapWidth,
          ),
        ),
        findsNothing,
      );
    });
  });
}
