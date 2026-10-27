import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_people_tags_repository.dart';

const _person = 'Uzed';

PersonAutoTagOf _auto(PersonAutoTagKind kind, {int n = 1}) => PersonAutoTagOf(
  kind: kind.smallintValue,
  n: n,
  direction: 0,
);

void main() {
  late PeopleTagsTestRig rig;

  Future<void> pumpBlockWith(
    WidgetTester tester,
    List<PersonAutoTagOf> autoTags,
  ) async {
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(autoByPerson: {_person: autoTags}),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: const TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: PersonTagsBlock(personId: _person),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  List<String> autoChipNames(WidgetTester tester) => tester
      .widgetList<AutoTagChip>(find.byType(AutoTagChip))
      .map((c) => c.name)
      .toList();

  group('person tags block automatic chips', () {
    testWidgets('several helped-me events for one person give one chip', (
      tester,
    ) async {
      await pumpBlockWith(tester, [
        for (var i = 0; i < 5; i++) _auto(PersonAutoTagKind.helpedMe),
      ]);

      final names = autoChipNames(tester);
      expect(names.where((n) => n.startsWith('Helped me')), hasLength(1));
      expect(names, hasLength(1));
    });

    testWidgets('every other automatic kind is shown once as well', (
      tester,
    ) async {
      const labelOf = <PersonAutoTagKind, String>{
        PersonAutoTagKind.mutualContact: 'Mutual contact',
        PersonAutoTagKind.iTrust: 'I trust',
        PersonAutoTagKind.trustsMe: 'Trusts me',
        PersonAutoTagKind.iHelped: 'I helped',
        PersonAutoTagKind.workedTogether: 'Worked together',
        PersonAutoTagKind.invited: 'Invited me / I invited',
        PersonAutoTagKind.forwarded: 'Forwarded to each other',
        PersonAutoTagKind.newOnField: 'New',
      };
      await pumpBlockWith(tester, [
        for (final kind in labelOf.keys) ...[
          _auto(kind),
          _auto(kind),
          _auto(kind),
        ],
      ]);

      final names = autoChipNames(tester);
      expect(names, hasLength(labelOf.length));
      for (final label in labelOf.values) {
        expect(
          names.where((n) => n.startsWith(label)),
          hasLength(1),
          reason: 'one "$label" chip expected, got $names',
        );
      }
    });

    testWidgets('repeated rows of mixed kinds keep one chip per kind', (
      tester,
    ) async {
      await pumpBlockWith(tester, [
        _auto(PersonAutoTagKind.helpedMe),
        _auto(PersonAutoTagKind.iTrust),
        _auto(PersonAutoTagKind.helpedMe),
        _auto(PersonAutoTagKind.helpedMe),
        _auto(PersonAutoTagKind.iTrust),
      ]);

      final names = autoChipNames(tester);
      expect(names, hasLength(2));
      expect(names.where((n) => n.startsWith('Helped me')), hasLength(1));
      expect(names.where((n) => n.startsWith('I trust')), hasLength(1));
    });
  });
}
