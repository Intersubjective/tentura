import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_sector_arrangement.dart';
import 'layout/layout_geometry.dart';

/// Most nodes one arrangement can move. The writes go to the outbox in
/// batches of `kConstellationPlacementBatchCap`.
const int kConstellationSectorMaxItems = 256;

/// How a rubber-band box changes the selection (#642).
enum ConstellationBoxMerge {
  /// The box's nodes become the selection.
  replace,

  /// The box's nodes join the selection (Shift, or a touch box).
  add,

  /// Each of the box's nodes flips in or out (Ctrl/Cmd).
  toggle,
}

/// Which part of the sector the user is dragging (#644).
enum ConstellationSectorEdge {
  /// The edge the sector starts from (counterclockwise on screen).
  start,

  /// The edge it ends at (clockwise on screen).
  end,
}

/// The sector the user is editing before the arrangement is written (#644):
/// a centre anywhere on the field, the inner and outer radius of the band the
/// nodes go in, and the sector's direction and width.
@immutable
final class ConstellationSectorDraft {
  const ConstellationSectorDraft({
    required this.centre,
    required this.radius,
    required this.direction,
    this.span = kConstellationSectorDefaultSpan,
    double outerRadius = 0,
    // A private field cannot be a named initializing formal.
    // ignore: prefer_initializing_formals
  }) : _outerRadius = outerRadius;

  /// Scene coordinates.
  final LPoint centre;

  /// Inner radius of the band: the first ring, in scene units.
  final double radius;

  final double _outerRadius;

  /// Outer radius of the band: the last ring, in scene units; never less
  /// than [radius] (one ring when they are equal).
  double get outerRadius => math.max(_outerRadius, radius);

  /// The sector's bisector: radians, scene coordinates (y down; 0 points
  /// right).
  final double direction;

  /// Sector width in radians, up to the whole circle.
  final double span;

  /// The angle the sector starts at (its [ConstellationSectorEdge.start]).
  double get start => direction - span / 2;

  /// The angle the sector ends at (its [ConstellationSectorEdge.end]).
  double get end => direction + span / 2;

  bool get isFullCircle => span >= kConstellationSectorMaxSpan - 1e-9;

  ConstellationSectorDraft copyWith({
    LPoint? centre,
    double? radius,
    double? outerRadius,
    double? direction,
    double? span,
  }) {
    final inner = math.max(0, radius ?? this.radius).toDouble();
    return ConstellationSectorDraft(
      centre: centre ?? this.centre,
      radius: inner,
      // An inner radius dragged past the outer one pushes it along.
      outerRadius: math.max(outerRadius ?? this.outerRadius, inner),
      direction: _normalize(direction ?? this.direction),
      span: (span ?? this.span).clamp(
        kConstellationSectorMinSpan,
        kConstellationSectorMaxSpan,
      ),
    );
  }

  /// [edge] turned by [delta] radians while the other edge stays put, as
  /// when dragging one side of a pie slice. The width stops at its limits.
  ConstellationSectorDraft withEdgeMoved(
    ConstellationSectorEdge edge,
    double delta,
  ) {
    switch (edge) {
      case ConstellationSectorEdge.end:
        final width = _clampSpan(span + delta);
        return copyWith(direction: start + width / 2, span: width);
      case ConstellationSectorEdge.start:
        final width = _clampSpan(span - delta);
        return copyWith(direction: end - width / 2, span: width);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ConstellationSectorDraft &&
      other.centre == centre &&
      other.radius == radius &&
      other.outerRadius == outerRadius &&
      other.direction == direction &&
      other.span == span;

  @override
  int get hashCode => Object.hash(centre, radius, outerRadius, direction, span);
}

double _clampSpan(double span) =>
    span.clamp(kConstellationSectorMinSpan, kConstellationSectorMaxSpan);

/// Field multi-selection (#642): people and Requests/Posts picked for a bulk
/// action. Selecting never changes the person panel or the focus spotlight.
@immutable
final class ConstellationMultiSelection {
  const ConstellationMultiSelection({
    this.selecting = false,
    this.targets = const {},
    this.sector,
  });

  static const empty = ConstellationMultiSelection();

  /// The toolbar toggle is on: a plain tap selects instead of opening.
  final bool selecting;

  /// Selected nodes in the order they were picked.
  final Set<ConstellationAnchorTarget> targets;

  /// Set while the user edits an «Arrange in sector».
  final ConstellationSectorDraft? sector;

  int get count => targets.length;

  bool get isEmpty => targets.isEmpty;

  /// The selection bar is shown.
  bool get isActive => selecting || targets.isNotEmpty;

  bool contains(ConstellationAnchorTarget target) => targets.contains(target);

  /// The other selected nodes that move with [grabbed] when it is dragged,
  /// as in a graphics editor: the rest of the selection when [grabbed] is
  /// part of it, nothing when it is not (it then moves alone and the
  /// selection stays as it is) or while a sector is being aimed.
  Set<ConstellationAnchorTarget> dragGroupFor(
    ConstellationAnchorTarget grabbed,
  ) => sector != null || !targets.contains(grabbed)
      ? const {}
      : {
          for (final target in targets)
            if (target != grabbed) target,
        };

  /// Whether the selection can be arranged in a sector: people, Requests
  /// and Posts alike, at least two of them.
  bool get canArrange => count >= 2 && count <= kConstellationSectorMaxItems;

  ConstellationMultiSelection toggle(ConstellationAnchorTarget target) {
    final next = {...targets};
    if (!next.remove(target)) next.add(target);
    return _with(targets: next);
  }

  ConstellationMultiSelection addAll(
    Iterable<ConstellationAnchorTarget> added,
  ) => _with(targets: {...targets, ...added});

  /// The nodes of a rubber-band box, merged as [merge] says.
  ConstellationMultiSelection applyBox(
    Iterable<ConstellationAnchorTarget> inside,
    ConstellationBoxMerge merge,
  ) => switch (merge) {
    ConstellationBoxMerge.replace => _with(targets: {...inside}),
    ConstellationBoxMerge.add => addAll(inside),
    ConstellationBoxMerge.toggle => _with(
      targets: {
        for (final target in targets)
          if (!inside.contains(target)) target,
        for (final target in inside)
          if (!targets.contains(target)) target,
      },
    ),
  };

  /// The select tool on or off; the selection itself stays.
  ConstellationMultiSelection withSelecting(bool selecting) =>
      _with(selecting: selecting);

  ConstellationMultiSelection withSector(ConstellationSectorDraft? sector) =>
      ConstellationMultiSelection(
        selecting: selecting,
        targets: targets,
        sector: sector,
      );

  /// A changed selection drops a sector being aimed at the old one.
  ConstellationMultiSelection _with({
    bool? selecting,
    Set<ConstellationAnchorTarget>? targets,
  }) {
    final nextTargets = targets ?? this.targets;
    return ConstellationMultiSelection(
      selecting: selecting ?? this.selecting,
      targets: Set.unmodifiable(nextTargets),
      sector: _sameTargets(nextTargets) ? sector : null,
    );
  }

  bool _sameTargets(Set<ConstellationAnchorTarget> other) =>
      const SetEquality<ConstellationAnchorTarget>().equals(targets, other);

  @override
  bool operator ==(Object other) =>
      other is ConstellationMultiSelection &&
      other.selecting == selecting &&
      other.sector == sector &&
      const ListEquality<ConstellationAnchorTarget>().equals(
        other.targets.toList(),
        targets.toList(),
      );

  @override
  int get hashCode => Object.hash(selecting, sector, Object.hashAll(targets));
}

double _normalize(double angle) {
  var result = angle % (2 * math.pi);
  if (result > math.pi) result -= 2 * math.pi;
  return result;
}
