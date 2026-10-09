import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
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

  final _showClosed = InputFieldBool(fieldName: 'showClosed');

  final _participatedOnly = InputFieldBool(fieldName: 'participatedOnly');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationAnchorsApply,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationAnchorsApply =>
      GraphQLObjectField(
        'constellationAnchorsApply',
        gqlTypeConstellationAnchorsApplyResult.nonNullable(),
        arguments: [
          _ops,
          _showClosed.field,
          _participatedOnly.field,
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
              params: AnchorApplyParams(
                context: kConstellationContext,
                filters: ConstellationFieldMembershipFilters(
                  showClosed: _showClosed.fromArgsNonNullable(args),
                  participatedOnly: _participatedOnly.fromArgsNonNullable(args),
                ),
              ),
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
    );
  }
}
