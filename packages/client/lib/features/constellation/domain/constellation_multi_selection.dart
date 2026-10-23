import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_sector_arrangement.dart';

/// Most people one arrangement can move: they are written as one batch.
const int kConstellationSectorMaxPeople = 64;

/// How a rubber-band box changes the selection (#642).
enum ConstellationBoxMerge {
  /// The box's nodes become the selection.
  replace,

  /// The box's nodes join the selection (Shift, or a touch box).
  add,

  /// Each of the box's nodes flips in or out (Ctrl/Cmd).
  toggle,
}

/// The sector the user is aiming before the arrangement is written (#644).
@immutable
final class ConstellationSectorDraft {
  const ConstellationSectorDraft({
    required this.direction,
    this.span = kConstellationSectorDefaultSpan,
  });

  /// Radians, scene coordinates (y down; 0 points right).
  final double direction;

  /// Requested sector width in radians; widened when people would not fit.
  final double span;

  ConstellationSectorDraft copyWith({double? direction, double? span}) =>
      ConstellationSectorDraft(
        direction: _normalize(direction ?? this.direction),
        span: (span ?? this.span).clamp(
          kConstellationSectorMinSpan,
          kConstellationSectorMaxSpan,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is ConstellationSectorDraft &&
      other.direction == direction &&
      other.span == span;

  @override
  int get hashCode => Object.hash(direction, span);
}

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

  /// Set while the user aims an «Arrange in sector».
  final ConstellationSectorDraft? sector;

  int get count => targets.length;

  bool get isEmpty => targets.isEmpty;

  /// The selection bar is shown.
  bool get isActive => selecting || targets.isNotEmpty;

  bool contains(ConstellationAnchorTarget target) => targets.contains(target);

  /// Ids of the selected people, in the order they were picked.
  List<String> get personIds => [
    for (final target in targets)
      if (target.kind == ConstellationAnchorTargetKind.person) target.id,
  ];

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

  /// Whether the selected people can be arranged in one batch.
  bool get canArrange {
    final people = personIds.length;
    return people >= 2 && people <= kConstellationSectorMaxPeople;
  }

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
