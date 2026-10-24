import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import 'fake_people_tags_repository.dart';

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

/// Two own tags: "Neighbours" holds [personId], "Climbers" holds somebody
/// else. An add-to-tag sheet opened for [personId] therefore shows
/// Neighbours ticked and Climbers unticked; one opened for anybody else shows
/// both unticked.
FakePeopleTagsRepository addToTagProbeRepository(String personId) =>
    FakePeopleTagsRepository(
      tagList: const [_neighbours, _climbers],
      memberList: [
        PersonTagMembers(tagId: 'Ta', personIds: [personId]),
        const PersonTagMembers(tagId: 'Tb', personIds: ['U-somebody-else']),
      ],
    );

/// The tag row of the open add-to-tag sheet named [tagName].
Finder _sheetRow(String tagName) =>
    find.widgetWithText(CheckboxListTile, tagName);

/// With the add-to-tag sheet open: asserts that it is the sheet (its title, its
/// "+ New tag" row and a row per tag are on screen) and that it is the
/// sheet of [personId] (that person's tag is ticked, the other tag is not).
/// Then ticks "Climbers", dismisses the sheet by tapping the dimmed area
/// outside it and asserts the single batch sent names [personId].
Future<void> expectAddToTagSheetIsForPerson(
  WidgetTester tester,
  FakePeopleTagsRepository repository,
  String personId,
) async {
  await tester.pumpAndSettle();
  // Sheet-only content: its "+ New tag" row and the tag rows. The title text
  // also labels the menu item or action that opened it, so it proves nothing
  // on its own.
  expect(find.text('+ New tag'), findsOneWidget);
  expect(find.byType(CheckboxListTile), findsNWidgets(2));
  expect(find.text('Add to tag…'), findsWidgets);

  expect(
    tester.widget<CheckboxListTile>(_sheetRow('Neighbours')).value,
    isTrue,
    reason: "the person's own tag is ticked",
  );
  expect(
    tester.widget<CheckboxListTile>(_sheetRow('Climbers')).value,
    isFalse,
    reason: "another person's tag is not ticked",
  );

  await tester.tap(_sheetRow('Climbers'));
  await tester.pump();
  // Tap the dimmed area outside the sheet; closing sends the batch.
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();

  expect(find.text('+ New tag'), findsNothing);
  expect(
    repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
    [('Tb', personId, true)],
  );
}
