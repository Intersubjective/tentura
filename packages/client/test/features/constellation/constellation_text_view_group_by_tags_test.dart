// The Field's list view can group people by the viewer's own tags: a section
// per tag in tag order with a count, a person under every tag they carry, and
// a trailing "without own tags" section. Selections on the tag row narrow the
// list; automatic tags only ever filter, they never become sections.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_row.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

const _groupToggle = Key('constellation.text.group_by_tags');
const _withoutTagsSection = Key('constellation.text.tag_section.none');

Key _section(String tagId) => Key('constellation.text.tag_section.$tagId');

Key _person(String id) => Key('constellation.text.person.$id');

/// People only (Ann: Neighbour, Workshop, Garden; Bob: Neighbour, Garden;
/// Cid: Garden; Dan: none), so every row of the list fits the viewport.
/// [cidAutoTags] marks Cid with automatic tags.
ConstellationField _peopleField({
  Set<ConstellationAutoTagKind> cidAutoTags = const {},
}) {
  final base = tagLensHarnessField();
  return base.copyWith(
    requests: const [],
    peers: [
      for (final peer in base.peers)
        if (peer.id == 'cid')
          peer.copyWith(autoTagKinds: cidAutoTags)
        else
          peer,
    ],
  );
}

Future<TagLensBodyHarness> _mountList(
  WidgetTester tester, {
  ConstellationField? field,
}) async {
  final mounted = await mountTagLensBody(
    tester,
    field: field ?? _peopleField(),
  );
  mounted.field.setViewMode(ConstellationViewMode.text);
  await settleTagLensBody(tester);
  return mounted;
}

Future<void> _groupByTags(WidgetTester tester) async {
  await tester.tap(find.byKey(_groupToggle));
  await settleTagLensBody(tester);
}

int _countOf(WidgetTester tester, Key sectionKey) {
  final header = tester.widget<TenturaSectionHeader>(find.byKey(sectionKey));
  return header.count!;
}

double _top(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder.first).dy;

/// Ids of the people whose row sits inside the section opened by
/// [sectionKey]: below its header and above the next header.
List<String> _peopleInSection(
  WidgetTester tester,
  Key sectionKey,
  List<Key> allSectionKeys,
) {
  final start = _top(tester, find.byKey(sectionKey));
  final following = [
    for (final key in allSectionKeys)
      if (find.byKey(key).evaluate().isNotEmpty &&
          _top(tester, find.byKey(key)) > start)
        _top(tester, find.byKey(key)),
  ]..sort();
  final end = following.isEmpty ? double.infinity : following.first;
  return [
    for (final id in const ['ann', 'bob', 'cid', 'dan'])
      for (final row in find.byKey(_person(id)).evaluate())
        if (tester.getTopLeft(find.byWidget(row.widget)).dy > start &&
            tester.getTopLeft(find.byWidget(row.widget)).dy < end)
          id,
  ];
}

/// Taps the chip of an own tag on the Field's tag row, by the tag's name.
Future<void> _tapTagRowChip(WidgetTester tester, String tagName) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ConstellationTagRow),
      matching: find.text(tagName),
    ),
  );
  await settleTagLensBody(tester);
}

void main() {
  final allSections = [
    _section(tagLensNeighbour.id),
    _section(tagLensWorkshop.id),
    _section(tagLensGarden.id),
    _section(tagLensEmpty.id),
    _withoutTagsSection,
  ];

  group('list view grouped by own tags', () {
    testWidgets('is a flat list until the grouping toggle is switched on', (
      tester,
    ) async {
      await _mountList(tester);

      expect(find.byKey(_groupToggle), findsOneWidget);
      for (final key in allSections) {
        expect(find.byKey(key), findsNothing);
      }
      for (final id in const ['ann', 'bob', 'cid', 'dan']) {
        expect(find.byKey(_person(id)), findsOneWidget, reason: id);
      }
    });

    testWidgets('shows a section per own tag in tag order with its count', (
      tester,
    ) async {
      await _mountList(tester);

      await _groupByTags(tester);

      expect(_countOf(tester, _section(tagLensNeighbour.id)), 2);
      expect(_countOf(tester, _section(tagLensWorkshop.id)), 1);
      expect(_countOf(tester, _section(tagLensGarden.id)), 3);
      // An own tag nobody on the field carries still gets its (empty) section.
      expect(_countOf(tester, _section(tagLensEmpty.id)), 0);
      // Tag order, then the "without own tags" section after every tag.
      final tops = [
        for (final key in allSections) _top(tester, find.byKey(key)),
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: 'section $i should come after section ${i - 1}',
        );
      }
    });

    testWidgets('lists a person with two tags in both of their sections', (
      tester,
    ) async {
      await _mountList(tester);

      await _groupByTags(tester);

      // Bob carries Neighbour and Garden; Ann carries all three tags.
      expect(find.byKey(_person('bob')), findsNWidgets(2));
      expect(find.byKey(_person('ann')), findsNWidgets(3));
      expect(
        _peopleInSection(tester, _section('T-neighbour'), allSections),
        unorderedEquals(['ann', 'bob']),
      );
      expect(
        _peopleInSection(tester, _section('T-workshop'), allSections),
        ['ann'],
      );
      expect(
        _peopleInSection(tester, _section('T-garden'), allSections),
        unorderedEquals(['ann', 'bob', 'cid']),
      );
    });

    testWidgets('puts people without any own tag in a last section', (
      tester,
    ) async {
      await _mountList(tester);

      await _groupByTags(tester);

      expect(_countOf(tester, _withoutTagsSection), 1);
      expect(
        _top(tester, find.byKey(_withoutTagsSection)),
        greaterThan(_top(tester, find.byKey(_section(tagLensEmpty.id)))),
      );
      expect(
        _peopleInSection(tester, _withoutTagsSection, allSections),
        ['dan'],
      );
      expect(find.byKey(_person('dan')), findsOneWidget);
    });

    testWidgets('returns to the flat list when the toggle is switched off', (
      tester,
    ) async {
      await _mountList(tester);
      await _groupByTags(tester);

      await _groupByTags(tester);

      for (final key in allSections) {
        expect(find.byKey(key), findsNothing);
      }
      for (final id in const ['ann', 'bob', 'cid', 'dan']) {
        expect(find.byKey(_person(id)), findsOneWidget, reason: id);
      }
    });
  });

  group('tag row selections narrow the grouped list', () {
    testWidgets('an own tag keeps only its members and shrinks the counts', (
      tester,
    ) async {
      final m = await _mountList(tester);
      await _groupByTags(tester);

      m.lens.toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      // Only Ann carries Workshop.
      expect(find.byKey(_person('ann')), findsNWidgets(3));
      for (final id in const ['bob', 'cid', 'dan']) {
        expect(find.byKey(_person(id)), findsNothing, reason: id);
      }
      expect(_countOf(tester, _section('T-neighbour')), 1);
      expect(_countOf(tester, _section('T-workshop')), 1);
      expect(_countOf(tester, _section('T-garden')), 1);
    });

    testWidgets('"all of them" keeps only people in every selected tag', (
      tester,
    ) async {
      final m = await _mountList(tester);
      await _groupByTags(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensGarden.id)
        ..setMode(ConstellationTagFilterMode.and);
      await settleTagLensBody(tester);

      // Ann and Bob remain, each under every tag they carry.
      expect(find.byKey(_person('ann')), findsNWidgets(3));
      expect(find.byKey(_person('bob')), findsNWidgets(2));
      expect(find.byKey(_person('cid')), findsNothing);
      expect(find.byKey(_person('dan')), findsNothing);
      expect(_countOf(tester, _section('T-neighbour')), 2);
      expect(_countOf(tester, _section('T-workshop')), 1);
      expect(_countOf(tester, _section('T-garden')), 2);
      expect(
        _peopleInSection(tester, _section('T-neighbour'), allSections),
        unorderedEquals(['ann', 'bob']),
      );
      expect(
        _peopleInSection(tester, _section('T-workshop'), allSections),
        ['ann'],
      );
      expect(
        _peopleInSection(tester, _section('T-garden'), allSections),
        unorderedEquals(['ann', 'bob']),
      );
    });

    testWidgets('clearing the selection restores the full sections', (
      tester,
    ) async {
      final m = await _mountList(tester);
      await _groupByTags(tester);
      m.lens.toggleOwn(tagLensWorkshop.id);
      await settleTagLensBody(tester);

      m.lens.clear();
      await settleTagLensBody(tester);

      expect(_countOf(tester, _section('T-neighbour')), 2);
      expect(_countOf(tester, _section('T-garden')), 3);
      expect(_countOf(tester, _withoutTagsSection), 1);
    });

    testWidgets('narrows the flat list too, while grouping is off', (
      tester,
    ) async {
      final m = await _mountList(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(find.byKey(_person('ann')), findsOneWidget);
      expect(find.byKey(_person('bob')), findsOneWidget);
      expect(find.byKey(_person('cid')), findsNothing);
      expect(find.byKey(_person('dan')), findsNothing);
    });

    testWidgets('an automatic tag filters people but adds no section', (
      tester,
    ) async {
      final m = await _mountList(
        tester,
        field: _peopleField(
          cidAutoTags: const {ConstellationAutoTagKind.mutualContact},
        ),
      );
      await _groupByTags(tester);

      m.lens.toggleAuto(ConstellationAutoTagKind.mutualContact);
      await settleTagLensBody(tester);

      // Only Cid is a mutual contact, and Cid carries only Garden.
      expect(find.byKey(_person('cid')), findsOneWidget);
      for (final id in const ['ann', 'bob', 'dan']) {
        expect(find.byKey(_person(id)), findsNothing, reason: id);
      }
      expect(_countOf(tester, _section('T-garden')), 1);
      final sectionKeys = {for (final key in allSections) key};
      final unexpectedSections = find.byWidgetPredicate(
        (w) =>
            w is TenturaSectionHeader &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'constellation.text.tag_section.',
            ) &&
            !sectionKeys.contains(w.key),
        description: 'a tag section for something other than an own tag',
      );
      expect(unexpectedSections, findsNothing);
    });
  });

  group('tapping a chip on the tag row narrows the list', () {
    testWidgets("keeps only that tag's members in the grouped list", (
      tester,
    ) async {
      await _mountList(tester);
      await _groupByTags(tester);

      await _tapTagRowChip(tester, tagLensWorkshop.name);

      expect(find.byKey(_person('ann')), findsNWidgets(3));
      for (final id in const ['bob', 'cid', 'dan']) {
        expect(find.byKey(_person(id)), findsNothing, reason: id);
      }
      expect(_countOf(tester, _section('T-neighbour')), 1);
      expect(_countOf(tester, _section('T-workshop')), 1);
      expect(_countOf(tester, _section('T-garden')), 1);
    });

    testWidgets("keeps only that tag's members in the flat list", (
      tester,
    ) async {
      await _mountList(tester);

      await _tapTagRowChip(tester, tagLensNeighbour.name);

      expect(find.byKey(_person('ann')), findsOneWidget);
      expect(find.byKey(_person('bob')), findsOneWidget);
      expect(find.byKey(_person('cid')), findsNothing);
      expect(find.byKey(_person('dan')), findsNothing);
    });

    testWidgets('tapping the chip again widens the list back', (tester) async {
      await _mountList(tester);
      await _groupByTags(tester);
      await _tapTagRowChip(tester, tagLensWorkshop.name);

      await _tapTagRowChip(tester, tagLensWorkshop.name);

      expect(_countOf(tester, _section('T-neighbour')), 2);
      expect(_countOf(tester, _section('T-garden')), 3);
      expect(_countOf(tester, _withoutTagsSection), 1);
    });
  });
}
