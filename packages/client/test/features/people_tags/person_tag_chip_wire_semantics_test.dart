import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/data/model/people_tags_mapper.dart';
import 'package:tentura/features/people_tags/ui/widget/person_auto_tag_name.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

void main() {
  testWidgets(
    'wire-mapped own tag chip speaks localized semantics on 375×667 RU',
    (tester) async {
      await usePhoneSurface(tester);
      final handle = tester.ensureSemantics();
      final l10n = lookupL10n(const Locale('ru'));

      final tag = mapPersonTag({
        'id': 'T1',
        'name': 'Соседи',
        'glyph': 'С',
        'color': 2,
        'ord': 0,
        'count': 1,
        'countOffField': 0,
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: Center(
                child: PersonTagChip(
                  glyph: tag.glyph,
                  name: tag.name,
                  colorIndex: tag.color,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(tag.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(l10n.peopleTagsPersonChipSemantics(tag.name)),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  testWidgets(
    'wire-mapped automatic tag kind speaks localized chip semantics',
    (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final en = lookupL10n(const Locale('en'));
      final autoTag = mapPersonAutoTag({
        'kind': 0,
        'count': 2,
        'showInFilters': true,
      });
      final name = personAutoTagName(en, autoTag.kind);

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: Center(child: AutoTagChip(name: name)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(en.peopleTagsAutoChipSemantics(name)),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
}
