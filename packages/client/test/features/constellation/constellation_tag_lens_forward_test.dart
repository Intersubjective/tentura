// "Forward a request…" on the tag lens panel lets the viewer pick one of
// their open Requests and opens that Request's forward screen with the
// selected tags carried along (`tags` query parameter, comma-separated tag
// ids), so the forward picker can preselect them. Only the viewer's own
// Requests that can still be forwarded are offered.

import 'package:flutter_test/flutter_test.dart';

import '../../support/constellation_tag_lens_body_harness.dart';

const _forwardLabel = 'Forward a request…';

/// How many widgets show [title] right now (the Field may label Requests too,
/// so the picker is judged by what it adds).
int _shown(String title) => find.text(title).evaluate().length;

Future<TagLensBodyHarness> _mount(WidgetTester tester) => mountTagLensBody(
  tester,
  field: tagLensHarnessFieldWithViewerRequests(),
  withRouter: true,
);

Future<void> _selectNeighbourAndGarden(
  WidgetTester tester,
  TagLensBodyHarness m,
) async {
  m.lens
    ..toggleOwn(tagLensNeighbour.id)
    ..toggleOwn(tagLensGarden.id);
  await settleTagLensBody(tester);
}

void main() {
  group('forward a request from the tag lens', () {
    testWidgets("offers the viewer's open Requests and no others", (
      tester,
    ) async {
      final m = await _mount(tester);
      await _selectNeighbourAndGarden(tester, m);
      final before = {
        for (final title in [
          'Borrow a drill',
          'Help moving',
          'Old closed errand',
          'Old cancelled errand',
          'Tools',
        ])
          title: _shown(title),
      };

      await tester.tap(find.text(_forwardLabel));
      await tester.pumpAndSettle();

      // Open and "needs more help" Requests of the viewer are offered.
      expect(_shown('Borrow a drill'), before['Borrow a drill']! + 1);
      expect(_shown('Help moving'), before['Help moving']! + 1);
      // Closed, cancelled and other people's Requests are not.
      expect(_shown('Old closed errand'), before['Old closed errand']);
      expect(_shown('Old cancelled errand'), before['Old cancelled errand']);
      expect(_shown('Tools'), before['Tools']);
    });

    testWidgets('opening the picker forwards nothing yet', (tester) async {
      final m = await _mount(tester);
      await _selectNeighbourAndGarden(tester, m);

      await tester.tap(find.text(_forwardLabel));
      await tester.pumpAndSettle();

      expect(find.text('forward-screen'), findsNothing);
      expect(m.router!.current.name, isNot('ForwardBeaconRoute'));
    });

    testWidgets("picking one opens that Request's forward screen with the "
        'selected tags', (tester) async {
      final m = await _mount(tester);
      await _selectNeighbourAndGarden(tester, m);
      await tester.tap(find.text(_forwardLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help moving').last);
      await tester.pumpAndSettle();

      expect(find.text('forward-screen'), findsOneWidget);
      final route = m.router!.current;
      expect(route.name, 'ForwardBeaconRoute');
      expect(route.params.getString('id'), 'mine-needs-help');
      expect(
        route.queryParams.getString('tags').split(',').toSet(),
        {tagLensNeighbour.id, tagLensGarden.id},
      );
    });

    testWidgets('the tags carried are the ones selected when picking', (
      tester,
    ) async {
      final m = await _mount(tester);
      await _selectNeighbourAndGarden(tester, m);
      // The selection changes after the panel first appeared.
      m.lens.toggleOwn(tagLensNeighbour.id);
      await settleTagLensBody(tester);

      await tester.tap(find.text(_forwardLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrow a drill').last);
      await tester.pumpAndSettle();

      final route = m.router!.current;
      expect(route.params.getString('id'), 'mine-open');
      expect(route.queryParams.getString('tags'), tagLensGarden.id);
    });
  });
}
