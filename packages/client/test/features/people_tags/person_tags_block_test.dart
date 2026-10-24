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

const _neighbours = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);
const _climbers = PersonTag(
  id: 'Tb',
  name: 'Climbers',
  glyph: 'C',
  color: 1,
  ord: 1,
);
const _cooks = PersonTag(
  id: 'Tc',
  name: 'Cooks',
  glyph: 'K',
  color: 2,
  ord: 2,
);

/// Neighbours and Climbers contain the person, Cooks does not.
FakePeopleTagsRepository _repository() => FakePeopleTagsRepository(
  tagList: [_cooks, _climbers, _neighbours],
  memberList: const [
    PersonTagMembers(tagId: 'Ta', personIds: [_person]),
    PersonTagMembers(tagId: 'Tb', personIds: [_person]),
    PersonTagMembers(tagId: 'Tc', personIds: ['Uother']),
  ],
  autoByPerson: {
    _person: [
      PersonAutoTagOf(
        kind: PersonAutoTagKind.mutualContact.smallintValue,
        n: 1,
        direction: 0,
      ),
      PersonAutoTagOf(
        kind: PersonAutoTagKind.iTrust.smallintValue,
        n: 1,
        direction: 1,
      ),
    ],
  },
);

void main() {
  late PeopleTagsTestRig rig;

  Future<void> setUpRig(FakePeopleTagsRepository repository) async {
    rig = await PeopleTagsTestRig.create(repository);
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  }

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  Future<void> pumpBlock(WidgetTester tester) async {
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

  Finder ownChip(String name) => find.byWidgetPredicate(
    (w) => w is PersonTagChip && w.name == name,
  );

  Finder removeButtonOf(String name) => find.descendant(
    of: ownChip(name),
    matching: find.byIcon(Icons.close),
  );

  group('person tags block', () {
    testWidgets('lists the own tags the person is in, in tag order, each '
        'with a remove button', (tester) async {
      await setUpRig(_repository());
      await pumpBlock(tester);

      expect(find.text('Your tags'), findsOneWidget);
      final chips = tester
          .widgetList<PersonTagChip>(find.byType(PersonTagChip))
          .toList();
      expect(chips.map((c) => c.name), ['Neighbours', 'Climbers']);
      expect(chips.map((c) => c.onRemove != null), [true, true]);
    });

    testWidgets('lists the automatic tags without a remove button', (
      tester,
    ) async {
      await setUpRig(_repository());
      await pumpBlock(tester);

      expect(find.text('Automatic'), findsOneWidget);
      expect(find.byType(AutoTagChip), findsNWidgets(2));
      expect(find.text('Mutual contact'), findsOneWidget);
      expect(find.text('I trust'), findsOneWidget);
      // The only × in the block belong to the two own tags.
      expect(
        find.descendant(
          of: find.byType(PersonTagsBlock),
          matching: find.byIcon(Icons.close),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byType(AutoTagChip),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
    });

    testWidgets('tells the person that only they see their tags', (
      tester,
    ) async {
      await setUpRig(_repository());
      await pumpBlock(tester);

      expect(find.textContaining('Only you see'), findsOneWidget);
    });

    testWidgets('the × removes that tag from the person and sends one '
        'remove op', (tester) async {
      final repository = _repository();
      await setUpRig(repository);
      await pumpBlock(tester);

      await tester.tap(removeButtonOf('Neighbours'));
      await tester.pumpAndSettle();

      expect(ownChip('Neighbours'), findsNothing);
      expect(ownChip('Climbers'), findsOneWidget);
      expect(repository.appliedOps, hasLength(1));
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        [('Ta', _person, false)],
      );
    });

    testWidgets('"+ Tag" opens the add-to-tag sheet for this person', (
      tester,
    ) async {
      await setUpRig(_repository());
      await pumpBlock(tester);

      await tester.tap(find.text('+ Tag'));
      await tester.pumpAndSettle();

      expect(find.text('Add to tag…'), findsOneWidget);
      // Tag order Neighbours, Climbers, Cooks; the person is in the first two.
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes.map((b) => b.value), [true, true, false]);
    });

    testWidgets('a person in no own tag still offers "+ Tag"', (tester) async {
      final repository = _repository()..memberList = const [];
      await setUpRig(repository);
      await pumpBlock(tester);

      expect(find.byType(PersonTagChip), findsNothing);
      expect(find.text('+ Tag'), findsOneWidget);
    });

    testWidgets('a tag added to the person elsewhere appears in the block', (
      tester,
    ) async {
      await setUpRig(_repository());
      await pumpBlock(tester);
      expect(ownChip('Cooks'), findsNothing);

      await rig.peopleTags.addToTag(personId: _person, tagId: 'Tc');
      await tester.pumpAndSettle();

      expect(ownChip('Cooks'), findsOneWidget);
    });
  });
}
