import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';

void main() {
  group('ConstellationZoomLevelController', () {
    test('settled scale picks the level as a pure function of scale', () {
      final c = ConstellationZoomLevelController();
      addTearDown(c.dispose);
      for (final s in [0.2, 0.44, 0.45, 0.6, 0.84, 0.85, 1.5]) {
        c.update(s, gestureActive: false);
        expect(c.value, settledConstellationDetailLevel(s), reason: '$s');
      }
    });

    test('a settled level does not depend on the path taken to the scale', () {
      final zoomedOut = ConstellationZoomLevelController()
        ..update(1.2, gestureActive: true)
        ..update(0.7, gestureActive: false);
      final zoomedIn = ConstellationZoomLevelController()
        ..update(0.2, gestureActive: true)
        ..update(0.7, gestureActive: false);
      addTearDown(zoomedOut.dispose);
      addTearDown(zoomedIn.dispose);
      expect(zoomedOut.value, zoomedIn.value);
      expect(zoomedOut.value, ConstellationDetailLevel.district);
    });

    test('hysteresis holds the level only while a gesture is active', () {
      final c = ConstellationZoomLevelController()
        ..update(1, gestureActive: true);
      addTearDown(c.dispose);
      final seen = <ConstellationDetailLevel>[];
      c.addListener(() => seen.add(c.value));
      for (final s in [0.852, 0.848, 0.852, 0.848, 0.852, 0.848]) {
        c.update(s, gestureActive: true);
      }
      expect(
        seen.length,
        lessThanOrEqualTo(1),
        reason: 'jitter on the 0.85 edge must not flicker mid-gesture',
      );
      c.update(0.848, gestureActive: false);
      expect(c.value, ConstellationDetailLevel.district);
      c.update(0.852, gestureActive: false);
      expect(c.value, ConstellationDetailLevel.close);
    });

    test('a settled scale ignores hysteresis, whatever came before', () {
      final c = ConstellationZoomLevelController()
        ..update(1, gestureActive: false)
        ..update(0.848, gestureActive: false);
      addTearDown(c.dispose);
      expect(c.value, ConstellationDetailLevel.district);
      c.update(0.448, gestureActive: false);
      expect(c.value, ConstellationDetailLevel.overview);
      c.update(0.452, gestureActive: false);
      expect(c.value, ConstellationDetailLevel.district);
    });
  });
}
