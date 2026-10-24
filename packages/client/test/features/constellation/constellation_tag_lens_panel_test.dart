// The bottom panel of the tag lens summarises the selection in one line
// ("tags · N people · M Requests") and offers "Forward a request…".
// "Open tag view" stays hidden until the tag view exists.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_tag_lens_panel.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

Finder _panel() => find.byType(ConstellationTagLensPanel);

Finder _inPanel(Finder finder) =>
    find.descendant(of: _panel(), matching: finder);

const _forwardLabel = 'Forward a request…';

/// Every text of the panel, in plain form.
List<String> _panelTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(_inPanel(find.byType(Text))))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

/// The one "{tags} · N people · M Requests" line of the panel.
String _summaryLine(WidgetTester tester) {
  final texts = _panelTexts(tester);
  final lines = [
    for (final text in texts)
      if (text.contains('people') && text.contains('Requests')) text,
  ];
  expect(lines, hasLength(1), reason: 'one summary line among $texts');
  return lines.single;
}

/// "{tags} · [people] people · [requests] Requests", the tags in [tags] order
/// with whatever separator between them.
Matcher _summary({
  required List<String> tags,
  required int people,
  required int requests,
}) => matches(
  RegExp(
    '^${tags.map(RegExp.escape).join('.*')}.* · $people people · '
    '$requests Requests\$',
  ),
);

void main() {
  group('tag lens bottom panel on the Field', () {
    testWidgets('there is no panel while no tag is selected', (tester) async {
      await mountTagLensBody(tester);

      expect(_panel(), findsNothing);
      expect(find.text(_forwardLabel), findsNothing);
    });

    testWidgets('one tag: one line "tag · N people · M Requests"', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_panel(), findsOneWidget);
      expect(_summaryLine(tester), 'Neighbour · 2 people · 3 Requests');
    });

    testWidgets('a larger tag counts more people and their Requests', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      expect(_summaryLine(tester), 'Garden · 3 people · 4 Requests');
    });

    testWidgets('several tags are all named and counted as a union', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);

      // Neighbour is inside Garden, so the union is Garden's three people.
      expect(
        _summaryLine(tester),
        _summary(tags: ['Neighbour', 'Garden'], people: 3, requests: 4),
      );
    });

    testWidgets('"all of them" counts only people in every selected tag', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens
        ..toggleOwn(tagLensNeighbour.id)
        ..toggleOwn(tagLensGarden.id)
        ..setMode(ConstellationTagFilterMode.and);
      await settleTagLensBody(tester);

      // Neighbour is inside Garden: the intersection is Neighbour's two
      // people (the union would be three).
      expect(
        _summaryLine(tester),
        _summary(tags: ['Neighbour', 'Garden'], people: 2, requests: 3),
      );

      m.lens.setMode(ConstellationTagFilterMode.or);
      await settleTagLensBody(tester);

      expect(
        _summaryLine(tester),
        _summary(tags: ['Neighbour', 'Garden'], people: 3, requests: 4),
      );
    });

    testWidgets('the line follows the selection as it changes', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);
      m.lens.toggleOwn(tagLensGarden.id);
      await settleTagLensBody(tester);
      expect(_summaryLine(tester), 'Garden · 3 people · 4 Requests');

      m.lens
        ..toggleOwn(tagLensGarden.id)
        ..toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_summaryLine(tester), 'Neighbour · 2 people · 3 Requests');
    });

    testWidgets('it offers "Forward a request…" and no "Open tag view"', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_inPanel(find.text(_forwardLabel)), findsOneWidget);
      expect(find.text('Open tag view'), findsNothing);
    });

    testWidgets('clearing the selection takes the panel away', (tester) async {
      final m = await mountTagLensBody(tester);
      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);
      expect(_panel(), findsOneWidget, reason: 'positive control');

      m.lens.clear();
      await settleTagLensBody(tester);

      expect(_panel(), findsNothing);
    });

    testWidgets('selecting a tag leaves every node where it was', (
      tester,
    ) async {
      final m = await mountTagLensBody(tester);
      final controller = m.field.graphController;
      final ids = [for (final n in controller.nodes) n.id];
      final positions = {
        for (final id in ids) id: controller.getPositionOrNullForId(id),
      };
      final cameraScale = controller.cameraScale;

      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      expect(_panel(), findsOneWidget, reason: 'positive control');
      for (final id in ids) {
        expect(
          controller.getPositionOrNullForId(id),
          positions[id],
          reason: id,
        );
      }
      expect(controller.cameraScale, cameraScale);
    });
  });
}
