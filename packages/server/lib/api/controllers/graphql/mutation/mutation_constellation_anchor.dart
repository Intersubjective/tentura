import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/constellation_gql_maps.dart';

/// `[ConstellationAnchorOpInput!]` typed over `dynamic`, so a decoded
/// `List<dynamic>` of maps passes validation on executors that do not
/// re-type variable lists.
final class _AnchorOpListType extends GraphQLListType<dynamic, dynamic> {
  _AnchorOpListType() : super(gqlInputConstellationAnchorOp.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}

final class MutationConstellationAnchor extends GqlNodeBase {
  MutationConstellationAnchor({
    ConstellationAnchorCase? constellationAnchorCase,
  }) : _constellationAnchorCase =
           constellationAnchorCase ?? GetIt.I<ConstellationAnchorCase>();

  final ConstellationAnchorCase _constellationAnchorCase;

  final _ops = GraphQLFieldInput('ops', _AnchorOpListType().nonNullable());

  final _clientOpId = GraphQLFieldInput(
    'clientOpId',
    graphQLString.nonNullable(),
  );

  static final _saveHistory = InputFieldBool(fieldName: 'saveHistory');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationAnchorsApply,
    constellationAnchorsReset,
  ];

  /// «Сбросить позиции» (#251): removes every user-placed position.
  GraphQLObjectField<dynamic, dynamic> get constellationAnchorsReset =>
      GraphQLObjectField(
        'constellationAnchorsReset',
        gqlTypeConstellationAnchorsResetResult.nonNullable(),
        arguments: [_clientOpId, _saveHistory.fieldNullable],
        resolve: (_, args) => _constellationAnchorCase
            .reset(
              viewerId: getCredentials(args).sub,
              clientOpId: args[_clientOpId.name]! as String,
              saveHistory: _saveHistory.fromArgsNonNullable(args),
            )
            .then(constellationAnchorsResetResultToGqlMap),
      );

  GraphQLObjectField<dynamic, dynamic> get constellationAnchorsApply =>
      GraphQLObjectField(
        'constellationAnchorsApply',
        gqlTypeConstellationAnchorsApplyResult.nonNullable(),
        arguments: [
          _ops,
        ],
        resolve: (_, args) {
          final viewerId = getCredentials(args).sub;
          return Future.sync(
            () => _constellationAnchorCase.apply(
              viewerId: viewerId,
              ops: [
                for (final raw in args[_ops.name]! as List)
                  _parseOp(viewerId, raw as Map),
              ],
            ),
          ).then(constellationAnchorsApplyResultToGqlMap);
        },
      );

  AnchorApplyOp _parseOp(String viewerId, Map<dynamic, dynamic> raw) {
    final position = raw['position'] as Map<dynamic, dynamic>?;
    return _constellationAnchorCase.parseOp(
      viewerId: viewerId,
      clientOpId: raw['clientOpId']! as String,
      kindWire: raw['kind']! as String,
      targetKindWire: raw['targetKind']! as String,
      targetId: raw['targetId']! as String,
      xUnits: (position?['xUnits'] as num?)?.toDouble(),
      yUnits: (position?['yUnits'] as num?)?.toDouble(),
      coordinateSpaceVersion: (position?['coordinateSpaceVersion'] as num?)
          ?.toInt(),
      ifRevisionWire: raw['ifRevision'] as String?,
      baseRevisionWire: raw['baseRevision'] as String?,
    );
  }
}
