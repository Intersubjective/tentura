import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

Gv2_ConstellationAnchorPositionInput anchorPositionToWire(
  ConstellationAnchorPosition position,
) => Gv2_ConstellationAnchorPositionInput(
  (builder) => builder
    ..xUnits = _graphQlFloatVariable(position.xUnits)
    ..yUnits = _graphQlFloatVariable(position.yUnits)
    ..coordinateSpaceVersion = position.coordinateSpaceVersion,
);

/// Whole-number doubles can serialize as integers on web. V2 Float! rejects them.
double _graphQlFloatVariable(double value) =>
    value == value.roundToDouble() ? value + 1e-9 : value;
