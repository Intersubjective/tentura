import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/phone_surface.dart';

const _longRuName = 'Соседи по даче в Подмосковье';

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

Finder _map() => find.byType(GraphView<NodeDetails, EdgeDetails>);

Future<void> _pumpTagRow(
  WidgetTester tester, {
  required Size surface,
  required List<PersonTag> ownTags,
  Locale locale = const Locale('ru'),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: ConstellationTagRow(
          ownTags: ownTags,
          autoTags: const [],
          filter: const ConstellationTagFilter(),
          onToggleOwn: (_) {},
          onToggleAuto: (_) {},
          onModeChanged: (_) {},
          onAddTag: () {},
          onShowAll: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpFieldWithManyTags(
  WidgetTester tester, {
  required Size bodySize,
  required Locale locale,
}) async {
  await tester.binding.setSurfaceSize(bodySize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await mountTagLensBody(
    tester,
    tagList: _manyRuTags(30),
    bodyBuilder: () => MediaQuery(
      data: MediaQueryData(size: bodySize),
      child: ConstellationBody(
        legendExpanded: false,
        onToggleLegend: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ConstellationTagRow scroll layout on phones', () {
    testWidgets('375×667 RU: row height ≤ 52 with 30 long-name tags', (
      tester,
    ) async {
      const body = Size(375, 547);
      await _pumpTagRow(
        tester,
        surface: body,
        ownTags: _manyRuTags(30),
      );
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;
      final maxRow = tt.buttonHeight + 2 * tt.tightGap;
      expect(
        tester.getSize(find.byType(ConstellationTagRow)).height,
        lessThanOrEqualTo(maxRow + 0.5),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('360×640 RU: row height ≤ 52 with 30 long-name tags', (
      tester,
    ) async {
      const body = Size(360, 520);
      await _pumpTagRow(
        tester,
        surface: body,
        ownTags: _manyRuTags(30),
      );
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;
      final maxRow = tt.buttonHeight + 2 * tt.tightGap;
      expect(
        tester.getSize(find.byType(ConstellationTagRow)).height,
        lessThanOrEqualTo(maxRow + 0.5),
      );
    });

    testWidgets('mode toggle stays in viewport with two tags selected', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      await _pumpTagRow(
        tester,
        surface: kPhoneSurface,
        ownTags: _manyRuTags(12),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ConstellationTagRow(
              ownTags: _manyRuTags(12),
              autoTags: const [],
              filter: const ConstellationTagFilter(
                selectedOwn: {'tag-0', 'tag-1'},
              ),
              onToggleOwn: (_) {},
              onToggleAuto: (_) {},
              onModeChanged: (_) {},
              onAddTag: () {},
              onShowAll: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggleRect = tester.getRect(
        find.byKey(ConstellationTagRow.modeToggleKey),
      );
      final screen = tester.getRect(find.byType(Scaffold));
      expect(screen.contains(toggleRect.topLeft), isTrue);
      expect(screen.contains(toggleRect.bottomRight), isTrue);
    });

    testWidgets('All tags sheet toggles lens and shows RU manage label', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final lens = ConstellationTagLensCubit();
      addTearDown(lens.close);
      final shortTags = [
        for (var i = 0; i < 5; i++)
          PersonTag(
            id: 'tag-$i',
            name: 'Тег $i',
            glyph: '$i',
            color: i,
            ord: i,
          ),
      ];
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
                body: Center(
                  child: TextButton(
                    onPressed: () => showConstellationAllTagsSheet(
                      context: context,
                      lensCubit: lens,
                      ownTags: shortTags,
                      autoTags: const [],
                      onAddTag: () {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Теги'), findsWidgets);
      expect(find.text('Управлять тегами'), findsOneWidget);
      await tester.tap(find.text('Тег 2'));
      await tester.pumpAndSettle();
      expect(lens.state.selectedOwn, contains('tag-2'));
    });
  });

  group('Field body top chrome cap', () {
    testWidgets('375×547 RU: map ≥ 443 px with 30 tags on the field', (
      tester,
    ) async {
      await _pumpFieldWithManyTags(
        tester,
        bodySize: const Size(375, 547),
        locale: const Locale('ru'),
      );
      final mapHeight = tester.getSize(_map()).height;
      expect(mapHeight, greaterThanOrEqualTo(443));
      expect(tester.takeException(), isNull);
    });

    testWidgets('360×520 RU: map ≥ 416 px with 30 tags on the field', (
      tester,
    ) async {
      await _pumpFieldWithManyTags(
        tester,
        bodySize: const Size(360, 520),
        locale: const Locale('ru'),
      );
      expect(tester.getSize(_map()).height, greaterThanOrEqualTo(416));
    });
  });
}
