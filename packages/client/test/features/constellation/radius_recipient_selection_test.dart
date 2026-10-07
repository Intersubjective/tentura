import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/radius_recipient_selection.dart';

void main() {
  const Map<String, LPoint> positions = {
    'near': (x: 3, y: 4),
    'middle': (x: 10, y: 0),
    'far': (x: 20, y: 0),
    'fourth': (x: 40, y: 0),
    'fifth': (x: 50, y: 0),
  };
  final eligible = positions.keys.toSet();

  RadiusRecipientSelection selection({double radius = 10}) =>
      RadiusRecipientSelection(
        center: (x: 0.0, y: 0.0),
        radius: radius,
        positions: positions,
        eligible: eligible,
      );

  test('includes the radius boundary using Euclidean distance', () {
    expect(selection(radius: 5).selected, {'near'});
    expect(selection(radius: 4.9).selected, isEmpty);
  });

  test('manual add survives shrinking', () {
    final original = selection();
    final updated = original.toggle('far').withRadius(1);
    expect(updated.selected, {'far'});
    expect(updated.manualAdded, {'far'});
    expect(original.selected, {'near', 'middle'});
    expect(original.manualAdded, isEmpty);
  });

  test('manual remove survives growing', () {
    final updated = selection().toggle('near').withRadius(100);
    expect(updated.selected, eligible.difference({'near'}));
    expect(updated.manualRemoved, {'near'});
  });

  test('ineligible and unknown people are never selected', () {
    final model = RadiusRecipientSelection(
      center: (x: 0.0, y: 0.0),
      radius: 100,
      positions: positions,
      eligible: const {'near'},
      manualAdded: const {'far', 'unknown'},
    );
    expect(model.selected, {'near'});
    expect(model.toggle('far').selected, {'near'});
    expect(model.toggle('unknown').selected, {'near'});
  });

  test('manual removal wins over manual addition', () {
    final model = RadiusRecipientSelection(
      center: (x: 0.0, y: 0.0),
      radius: 100,
      positions: positions,
      eligible: eligible,
      manualAdded: const {'far'},
      manualRemoved: const {'far'},
    );
    expect(model.selected, eligible.difference({'far'}));
    final toggled = model.toggle('far');
    expect(toggled.manualRemoved, isEmpty);
    expect(toggled.selected, eligible);
  });

  test('toggle twice restores selection inside and outside radius', () {
    final original = selection();
    for (final id in ['near', 'far']) {
      expect(original.toggle(id).toggle(id).selected, original.selected);
    }
    expect(original.toggle('far').toggle('far').manualAdded, isEmpty);
    expect(original.toggle('near').toggle('near').manualRemoved, isEmpty);
  });

  test('moving the center recomputes membership and retains overrides', () {
    final original = selection(radius: 1).toggle('near');
    final moved = original.withCenter((x: 20, y: 0));
    expect(moved.selected, {'near', 'far'});
    expect(moved.manualAdded, {'near'});
    expect(original.center, (x: 0.0, y: 0.0));
    expect(moved.radius, original.radius);
  });

  test('startRadius covers exactly three of five eligible people', () {
    final radius = RadiusRecipientSelection.startRadius(
      (x: 0.0, y: 0.0),
      positions,
      eligible,
    );
    expect(radius, closeTo(22, 1e-10));
    expect(selection(radius: radius).selected, {'near', 'middle', 'far'});
  });

  test(
    'startRadius uses the farthest when fewer than three are positioned',
    () {
      expect(
        RadiusRecipientSelection.startRadius(
          (x: 0.0, y: 0.0),
          positions,
          {'near', 'middle', 'missing'},
        ),
        closeTo(11, 1e-10),
      );
      expect(
        RadiusRecipientSelection.startRadius((x: 0.0, y: 0.0), positions, {'near'}),
        closeTo(5.5, 1e-10),
      );
    },
  );

  test('startRadius measures from center and ignores ineligible positions', () {
    expect(
      RadiusRecipientSelection.startRadius(
        (x: 10, y: 0),
        positions,
        {'far'},
      ),
      closeTo(11, 1e-10),
    );
  });

  test('startRadius falls back to minimum without eligible positions', () {
    for (final ids in [
      <String>{},
      {'missing'},
    ]) {
      expect(
        RadiusRecipientSelection.startRadius((x: 0.0, y: 0.0), positions, ids),
        kComposerMinRadius,
      );
    }
    expect(kComposerMinRadius, greaterThan(0));
  });

  test('collections are defensively copied and immutable', () {
    final mutablePositions = <String, LPoint>{'near': (x: 3, y: 4)};
    final mutableEligible = {'near', 'far'};
    final added = {'far'};
    final removed = <String>{};
    final model = RadiusRecipientSelection(
      center: (x: 0.0, y: 0.0),
      radius: 5,
      positions: mutablePositions,
      eligible: mutableEligible,
      manualAdded: added,
      manualRemoved: removed,
    );
    mutablePositions.clear();
    mutableEligible.clear();
    added.clear();
    removed.add('near');
    expect(model.selected, {'near', 'far'});
    expect(model.positions.clear, throwsUnsupportedError);
    expect(model.eligible.clear, throwsUnsupportedError);
    expect(model.manualAdded.clear, throwsUnsupportedError);
    expect(model.manualRemoved.clear, throwsUnsupportedError);
    expect(() => model.selected.clear(), throwsUnsupportedError);
  });
}
