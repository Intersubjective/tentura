// Tag-picked recipients of the composer circle: the selection is
// (inRadius ∪ manualAdded ∪ tagAdded) \ manualRemoved, and removing a tag
// takes back only the people that tag added on its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/radius_recipient_selection.dart';

void main() {
  const positions = <String, LPoint>{
    'near': (x: 3, y: 4),
    'middle': (x: 10, y: 0),
    'far': (x: 20, y: 0),
    'fourth': (x: 40, y: 0),
    'fifth': (x: 50, y: 0),
  };
  final eligible = positions.keys.toSet();

  RadiusRecipientSelection selection({
    double radius = 10,
    Set<String>? eligibleIds,
    Map<String, LPoint> people = positions,
  }) => RadiusRecipientSelection(
    center: (x: 0.0, y: 0.0),
    radius: radius,
    positions: people,
    eligible: eligibleIds ?? eligible,
  );

  group('adding a tag', () {
    test('selects the tag members outside the circle', () {
      final updated = selection().addByTag('t1', ['far', 'fourth']);

      expect(updated.selected, {'near', 'middle', 'far', 'fourth'});
    });

    test('leaves the original selection untouched', () {
      final original = selection()..addByTag('t1', ['far']);

      expect(original.selected, {'near', 'middle'});
    });

    test('selects members who have no position', () {
      final model = selection(
        eligibleIds: {...eligible, 'unplaced'},
      ).addByTag('t1', ['unplaced']);

      expect(model.selected, {'near', 'middle', 'unplaced'});
    });

    test('ignores members who are not eligible', () {
      final model = selection(
        eligibleIds: {'near', 'middle', 'far'},
      ).addByTag('t1', ['far', 'fourth', 'stranger']);

      expect(model.selected, {'near', 'middle', 'far'});
    });

    test('keeps a tag member the viewer removed by hand excluded', () {
      final model = selection().toggle('near').addByTag('t1', ['near', 'far']);

      expect(model.selected, {'middle', 'far'});
    });

    test('keeps the tag people when the circle shrinks', () {
      final model = selection().addByTag('t1', ['far']).withRadius(1);

      expect(model.selected, {'far'});
    });

    test('keeps the tag people when the circle moves away', () {
      final model = selection(
        radius: 5,
      ).addByTag('t1', ['fifth']).withCenter((x: 100, y: 0));

      expect(model.selected, {'fifth'});
    });
  });

  group('removing a tag', () {
    test('takes back the people it added outside the circle', () {
      final model = selection()
          .addByTag('t1', ['far', 'fourth'])
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle'});
    });

    test('keeps tag members who are inside the circle', () {
      final model = selection()
          .addByTag('t1', ['near', 'far'])
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle'});
    });

    test('keeps tag members who were added individually before the tag', () {
      final model = selection()
          .toggle('far')
          .addByTag('t1', ['far', 'fourth'])
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle', 'far'});
    });

    test('keeps tag members who were added individually after the tag', () {
      final model = selection()
          .addByTag('t1', ['far', 'fourth'])
          .addManually('far')
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle', 'far'});
    });

    test('keeps people another active tag also picked', () {
      final model = selection()
          .addByTag('t1', ['far', 'fourth'])
          .addByTag('t2', ['fourth', 'fifth'])
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle', 'fourth', 'fifth'});
      expect(model.removeByTag('t2').selected, {'near', 'middle'});
    });

    test('takes back tag members the circle grew over only while they stay '
        'outside', () {
      final model = selection()
          .addByTag('t1', ['far'])
          .withRadius(25)
          .removeByTag('t1');

      // 'far' is now inside the circle, so it stays.
      expect(model.selected, {'near', 'middle', 'far'});
      expect(model.withRadius(10).selected, {'near', 'middle'});
    });

    test('an inactive tag changes nothing', () {
      final original = selection().toggle('far');

      expect(original.removeByTag('never-added').selected, original.selected);
    });

    test('adding the same tag twice and removing it once leaves no trace', () {
      final model = selection()
          .addByTag('t1', ['far'])
          .addByTag('t1', ['far'])
          .removeByTag('t1');

      expect(model.selected, {'near', 'middle'});
    });
  });

  test('tag, radius and manual edits combine as in-radius, added and tag '
      'minus removed', () {
    final model = selection()
        .toggle('middle') // removed by hand, inside the circle
        .toggle('far') // added by hand, outside the circle
        .addByTag('t1', ['fourth', 'middle'])
        .addByTag('t2', ['fifth']);

    expect(model.selected, {'near', 'far', 'fourth', 'fifth'});

    final withoutT1 = model.removeByTag('t1');
    expect(withoutT1.selected, {'near', 'far', 'fifth'});
    expect(withoutT1.removeByTag('t2').selected, {'near', 'far'});
  });

  test('the selection stays immutable', () {
    final model = selection().addByTag('t1', ['far']);

    expect(() => model.selected.clear(), throwsUnsupportedError);
  });
}
