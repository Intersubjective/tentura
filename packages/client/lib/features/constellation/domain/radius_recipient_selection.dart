import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

/// Initial scene-space radius when no eligible person has a position.
const double kComposerMinRadius = 40;

/// Radius-based recipients with persistent manual selection overrides.
@immutable
final class RadiusRecipientSelection {
  /// Takes immutable snapshots of positions, eligibility and overrides.
  RadiusRecipientSelection({
    required this.center,
    required this.radius,
    required Map<String, Offset> positions,
    required Set<String> eligible,
    Set<String> manualAdded = const {},
    Set<String> manualRemoved = const {},
  }) : positions = Map<String, Offset>.unmodifiable(positions),
       eligible = Set<String>.unmodifiable(eligible),
       manualAdded = Set<String>.unmodifiable(manualAdded),
       manualRemoved = Set<String>.unmodifiable(manualRemoved);

  /// Center of the selection circle in scene coordinates.
  final Offset center;

  /// Inclusive distance from [center] for automatic selection.
  final double radius;

  /// Scene positions keyed by person id.
  final Map<String, Offset> positions;

  /// People who may be selected, including those without a position.
  final Set<String> eligible;

  /// People selected independently of the radius.
  final Set<String> manualAdded;

  /// People excluded independently of the radius; removal wins over addition.
  final Set<String> manualRemoved;

  /// Eligible recipients inside the circle or manually added, minus removals.
  Set<String> get selected => Set<String>.unmodifiable({
    for (final id in eligible)
      if (!manualRemoved.contains(id) &&
          (manualAdded.contains(id) ||
              (positions.containsKey(id) &&
                  (positions[id]! - center).distance <= radius)))
        id,
  });

  /// Toggles effective membership and clears the opposite manual override.
  RadiusRecipientSelection toggle(String id) {
    final added = {...manualAdded};
    final removed = {...manualRemoved};
    if (selected.contains(id)) {
      final inRadius =
          positions.containsKey(id) &&
          (positions[id]! - center).distance <= radius;
      // Outside the circle, dropping the manual addition is the whole undo.
      if (inRadius) removed.add(id);
      added.remove(id);
    } else {
      added.add(id);
      removed.remove(id);
    }
    return _copyWith(manualAdded: added, manualRemoved: removed);
  }

  /// Changes the circle radius while preserving all manual overrides.
  RadiusRecipientSelection withRadius(double radius) =>
      _copyWith(radius: radius);

  /// Moves the circle while preserving all manual overrides.
  RadiusRecipientSelection withCenter(Offset center) =>
      _copyWith(center: center);

  RadiusRecipientSelection _copyWith({
    Offset? center,
    double? radius,
    Set<String>? manualAdded,
    Set<String>? manualRemoved,
  }) => RadiusRecipientSelection(
    center: center ?? this.center,
    radius: radius ?? this.radius,
    positions: positions,
    eligible: eligible,
    manualAdded: manualAdded ?? this.manualAdded,
    manualRemoved: manualRemoved ?? this.manualRemoved,
  );

  /// Covers the third-nearest eligible position with ten percent extra room.
  ///
  /// With fewer than three positions, uses the farthest. Without eligible
  /// positions, returns [kComposerMinRadius].
  static double startRadius(
    Offset center,
    Map<String, Offset> positions,
    Set<String> eligible,
  ) {
    final distances = [
      for (final entry in positions.entries)
        if (eligible.contains(entry.key)) (entry.value - center).distance,
    ]..sort();
    if (distances.isEmpty) {
      return kComposerMinRadius;
    }
    return distances[distances.length < 3 ? distances.length - 1 : 2] * 1.1;
  }
}
