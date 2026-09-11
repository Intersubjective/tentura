import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/constellation_gql_maps.dart';

final class MutationConstellationAnchor extends GqlNodeBase {
  MutationConstellationAnchor({ConstellationAnchorCase? constellationAnchorCase})
    : _constellationAnchorCase =
          constellationAnchorCase ?? GetIt.I<ConstellationAnchorCase>();

  final ConstellationAnchorCase _constellationAnchorCase;

  final _targetKind = GraphQLFieldInput(
    'targetKind',
    gqlEnumConstellationAnchorTargetKind.nonNullable(),
  );

  final _targetId = InputFieldString(fieldName: 'targetId');

  final _xUnits = InputFieldFloat(fieldName: 'xUnits');

  final _yUnits = InputFieldFloat(fieldName: 'yUnits');

  final _coordinateSpaceVersion = InputFieldInt(fieldName: 'coordinateSpaceVersion');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationAnchorUpsert,
    constellationAnchorDelete,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationAnchorUpsert =>
      GraphQLObjectField(
        'constellationAnchorUpsert',
        gqlTypeConstellationAnchorUpsertResult.nonNullable(),
        arguments: [
          _targetKind,
          _targetId.field,
          _xUnits.fieldNonNullable,
          _yUnits.fieldNonNullable,
          _coordinateSpaceVersion.fieldNonNullable,
        ],
        resolve: (_, args) => _constellationAnchorCase
            .upsert(
              viewerId: getCredentials(args).sub,
              targetKindWire: args[_targetKind.name]! as String,
              targetId: _targetId.fromArgsNonNullable(args),
              xUnits: _xUnits.fromArgsNonNullable(args),
              yUnits: _yUnits.fromArgsNonNullable(args),
              coordinateSpaceVersion:
                  _coordinateSpaceVersion.fromArgsNonNullable(args),
            )
            .then(constellationAnchorUpsertResultToGqlMap),
      );

  GraphQLObjectField<dynamic, dynamic> get constellationAnchorDelete =>
      GraphQLObjectField(
        'constellationAnchorDelete',
        gqlTypeConstellationAnchorDeleteResult.nonNullable(),
        arguments: [
          _targetKind,
          _targetId.field,
        ],
        resolve: (_, args) => _constellationAnchorCase
            .delete(
              viewerId: getCredentials(args).sub,
              targetKindWire: args[_targetKind.name]! as String,
              targetId: _targetId.fromArgsNonNullable(args),
            )
            .then(constellationAnchorDeleteResultToGqlMap),
      );
}
