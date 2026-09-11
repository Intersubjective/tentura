import 'package:meta/meta.dart';

import '../constellation_consts.dart';

/// Wire / GraphQL target kind for constellation anchors (C1).
enum ConstellationAnchorTargetKind {
  person('PERSON'),
  beacon('BEACON');

  const ConstellationAnchorTargetKind(this.wireValue);

  final String wireValue;

  static ConstellationAnchorTargetKind? fromWire(String wire) => switch (wire) {
        'PERSON' => ConstellationAnchorTargetKind.person,
        'BEACON' => ConstellationAnchorTargetKind.beacon,
        _ => null,
      };

  /// Lexical paint-order tie-break (C1): `BEACON` before `PERSON`.
  String get paintOrderKey => wireValue;
}

/// Sealed pin target; never key anchor maps by naked [id] alone (C1).
@immutable
sealed class ConstellationAnchorTarget {
  const ConstellationAnchorTarget();

  String get id;

  ConstellationAnchorTargetKind get kind;

  /// Existing graph / field node id (no re-keying at this boundary).
  String get graphNodeId => id;

  String get mapKey => '${kind.wireValue}:$id';

  /// True when this person target is the authenticated viewer (ego cannot pin).
  bool isViewerEgo(String viewerId) =>
      kind == ConstellationAnchorTargetKind.person && id == viewerId;

  static ConstellationAnchorTarget person(String id) =>
      ConstellationAnchorPersonTarget(id);

  static ConstellationAnchorTarget beacon(String id) =>
      ConstellationAnchorBeaconTarget(id);

  static ConstellationAnchorTarget? tryFromWire({
    required String kindWire,
    required String targetId,
  }) {
    final kind = ConstellationAnchorTargetKind.fromWire(kindWire);
    if (kind == null) {
      return null;
    }
    return switch (kind) {
      ConstellationAnchorTargetKind.person =>
        ConstellationAnchorPersonTarget(targetId),
      ConstellationAnchorTargetKind.beacon =>
        ConstellationAnchorBeaconTarget(targetId),
    };
  }
}

@immutable
final class ConstellationAnchorPersonTarget extends ConstellationAnchorTarget {
  const ConstellationAnchorPersonTarget(this.id);

  @override
  final String id;

  @override
  ConstellationAnchorTargetKind get kind => ConstellationAnchorTargetKind.person;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchorPersonTarget && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

@immutable
final class ConstellationAnchorBeaconTarget extends ConstellationAnchorTarget {
  const ConstellationAnchorBeaconTarget(this.id);

  @override
  final String id;

  @override
  ConstellationAnchorTargetKind get kind => ConstellationAnchorTargetKind.beacon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchorBeaconTarget && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Domain failures for anchor target validation (wire mapping lives in data/API).
@immutable
sealed class ConstellationAnchorTargetValidation {
  const ConstellationAnchorTargetValidation();
}

@immutable
final class ConstellationAnchorTargetValid
    extends ConstellationAnchorTargetValidation {
  const ConstellationAnchorTargetValid(this.target);

  final ConstellationAnchorTarget target;
}

@immutable
final class ConstellationAnchorTargetInvalid
    extends ConstellationAnchorTargetValidation {
  const ConstellationAnchorTargetInvalid(this.reason);

  final ConstellationAnchorTargetInvalidReason reason;
}

enum ConstellationAnchorTargetInvalidReason {
  emptyId,
  invalidEgoPerson,
  unknownWireKind,
}

ConstellationAnchorTargetValidation validateConstellationAnchorTarget({
  required ConstellationAnchorTarget? target,
  required String viewerId,
}) {
  if (target == null) {
    return const ConstellationAnchorTargetInvalid(
      ConstellationAnchorTargetInvalidReason.unknownWireKind,
    );
  }
  if (target.id.isEmpty) {
    return const ConstellationAnchorTargetInvalid(
      ConstellationAnchorTargetInvalidReason.emptyId,
    );
  }
  if (target.isViewerEgo(viewerId)) {
    return const ConstellationAnchorTargetInvalid(
      ConstellationAnchorTargetInvalidReason.invalidEgoPerson,
    );
  }
  return ConstellationAnchorTargetValid(target);
}

@immutable
sealed class ConstellationAnchorPositionValidation {
  const ConstellationAnchorPositionValidation();
}

@immutable
final class ConstellationAnchorPositionValid
    extends ConstellationAnchorPositionValidation {
  const ConstellationAnchorPositionValid(this.position);

  final ConstellationAnchorPosition position;
}

@immutable
final class ConstellationAnchorPositionInvalid
    extends ConstellationAnchorPositionValidation {
  const ConstellationAnchorPositionInvalid(this.reason);

  final ConstellationAnchorPositionInvalidReason reason;
}

enum ConstellationAnchorPositionInvalidReason {
  nonFinite,
  outOfRange,
  unsupportedCoordinateSpace,
}

/// Normalized ego-relative anchor coordinates (C1 / D19).
@immutable
class ConstellationAnchorPosition {
  const ConstellationAnchorPosition({
    required this.xUnits,
    required this.yUnits,
    required this.coordinateSpaceVersion,
  });

  final double xUnits;
  final double yUnits;
  final int coordinateSpaceVersion;

  static bool isFiniteV1Axis(double value) =>
      value.isFinite &&
      value >= kConstellationCoordinateMinUnits &&
      value <= kConstellationCoordinateMaxUnits;

  static ConstellationAnchorPositionValidation validate({
    required double xUnits,
    required double yUnits,
    required int coordinateSpaceVersion,
  }) {
    if (coordinateSpaceVersion != kConstellationCoordinateSpaceVersionV1) {
      return const ConstellationAnchorPositionInvalid(
        ConstellationAnchorPositionInvalidReason.unsupportedCoordinateSpace,
      );
    }
    if (!xUnits.isFinite || !yUnits.isFinite) {
      return const ConstellationAnchorPositionInvalid(
        ConstellationAnchorPositionInvalidReason.nonFinite,
      );
    }
    if (!isFiniteV1Axis(xUnits) || !isFiniteV1Axis(yUnits)) {
      return const ConstellationAnchorPositionInvalid(
        ConstellationAnchorPositionInvalidReason.outOfRange,
      );
    }
    return ConstellationAnchorPositionValid(
      ConstellationAnchorPosition(
        xUnits: xUnits,
        yUnits: yUnits,
        coordinateSpaceVersion: coordinateSpaceVersion,
      ),
    );
  }

  Map<String, Object> toFixtureMap() => {
        'xUnits': xUnits,
        'yUnits': yUnits,
        'coordinateSpaceVersion': coordinateSpaceVersion,
      };

  static ConstellationAnchorPositionValidation fromFixtureMap(
    Map<String, Object?> map,
  ) {
    final x = map['xUnits'];
    final y = map['yUnits'];
    final version = map['coordinateSpaceVersion'];
    if (x is! num || y is! num || version is! int) {
      return const ConstellationAnchorPositionInvalid(
        ConstellationAnchorPositionInvalidReason.nonFinite,
      );
    }
    return validate(
      xUnits: x.toDouble(),
      yUnits: y.toDouble(),
      coordinateSpaceVersion: version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchorPosition &&
          other.xUnits == xUnits &&
          other.yUnits == yUnits &&
          other.coordinateSpaceVersion == coordinateSpaceVersion;

  @override
  int get hashCode => Object.hash(xUnits, yUnits, coordinateSpaceVersion);
}

@immutable
sealed class ConstellationAnchorRevisionParseResult {
  const ConstellationAnchorRevisionParseResult();
}

@immutable
final class ConstellationAnchorRevisionParsed
    extends ConstellationAnchorRevisionParseResult {
  const ConstellationAnchorRevisionParsed(this.revision);

  final ConstellationAnchorRevision revision;
}

@immutable
final class ConstellationAnchorRevisionMalformed
    extends ConstellationAnchorRevisionParseResult {
  const ConstellationAnchorRevisionMalformed();
}

/// Account-wide monotonic revision; GraphQL encodes as decimal string (C1).
@immutable
class ConstellationAnchorRevision {
  const ConstellationAnchorRevision(this.value);

  final BigInt value;

  static final zero = ConstellationAnchorRevision(BigInt.zero);

  static ConstellationAnchorRevisionParseResult parseDecimalString(
    String wire,
  ) {
    final trimmed = wire.trim();
    if (trimmed.isEmpty || trimmed.startsWith('-')) {
      return const ConstellationAnchorRevisionMalformed();
    }
    try {
      return ConstellationAnchorRevisionParsed(
        ConstellationAnchorRevision(BigInt.parse(trimmed)),
      );
    } on FormatException {
      return const ConstellationAnchorRevisionMalformed();
    }
  }

  String toDecimalString() => value.toString();

  int compareTo(ConstellationAnchorRevision other) =>
      value.compareTo(other.value);

  Map<String, Object> toFixtureMap() => {'revision': toDecimalString()};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchorRevision && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class ConstellationAnchor {
  const ConstellationAnchor({
    required this.target,
    required this.position,
    required this.revision,
    required this.placedAt,
  });

  final ConstellationAnchorTarget target;
  final ConstellationAnchorPosition position;
  final ConstellationAnchorRevision revision;
  final DateTime placedAt;

  /// Stable ascending paint order; later entries are topmost (C1 / D22).
  static int comparePaintOrder(ConstellationAnchor a, ConstellationAnchor b) {
    final placed = a.placedAt.compareTo(b.placedAt);
    if (placed != 0) {
      return placed;
    }
    final kind = a.target.kind.paintOrderKey.compareTo(
      b.target.kind.paintOrderKey,
    );
    if (kind != 0) {
      return kind;
    }
    return a.target.id.compareTo(b.target.id);
  }

  Map<String, Object> toFixtureMap() => {
        'targetKind': target.kind.wireValue,
        'targetId': target.id,
        ...position.toFixtureMap(),
        ...revision.toFixtureMap(),
        'placedAt': placedAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationAnchor &&
          other.target == target &&
          other.position == position &&
          other.revision == revision &&
          other.placedAt == placedAt;

  @override
  int get hashCode => Object.hash(target, position, revision, placedAt);
}

/// V1 normalized units → render-space centre (pure; adapter supplies centre).
({double x, double y}) constellationV1UnitsToRenderCentre({
  required double renderCentreX,
  required double renderCentreY,
  required double xUnits,
  required double yUnits,
}) {
  return (
    x: renderCentreX + xUnits * kConstellationRingUnitPixels,
    y: renderCentreY + yUnits * kConstellationRingUnitPixels,
  );
}

({double xUnits, double yUnits}) constellationRenderCentreToV1Units({
  required double renderCentreX,
  required double renderCentreY,
  required double renderX,
  required double renderY,
}) {
  return (
    xUnits: (renderX - renderCentreX) / kConstellationRingUnitPixels,
    yUnits: (renderY - renderCentreY) / kConstellationRingUnitPixels,
  );
}
