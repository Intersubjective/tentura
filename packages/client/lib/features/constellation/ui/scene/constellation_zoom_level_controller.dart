import 'package:flutter/foundation.dart';

import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';

/// The one owner of the map's zoom level, read by the body and the viewport
/// overlay so they always agree.
///
/// A settled scale picks the level as a pure function of the scale. Only
/// while a gesture is active does the level hold back near a threshold, so a
/// pinch jittering on an edge does not flicker.
///
/// Deliberately not a [Listenable] itself: it is handed down through a
/// `Provider`, which rejects Listenable values. Listen via [changes].
class ConstellationZoomLevelController {
  /// Half-width of the band around a threshold that a gesture must clear.
  static const _gestureMargin = 0.03;

  final _level = ValueNotifier(ConstellationDetailLevel.close);

  ConstellationDetailLevel get value => _level.value;

  ValueListenable<ConstellationDetailLevel> get changes => _level;

  void addListener(VoidCallback listener) => _level.addListener(listener);

  void removeListener(VoidCallback listener) => _level.removeListener(listener);

  void update(double scale, {required bool gestureActive}) {
    final next = settledConstellationDetailLevel(scale);
    if (next == value) return;
    if (gestureActive &&
        (settledConstellationDetailLevel(scale + _gestureMargin) != next ||
            settledConstellationDetailLevel(scale - _gestureMargin) != next)) {
      return;
    }
    _level.value = next;
  }

  void dispose() => _level.dispose();
}
