import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCapabilityProjection extends GqlNodeBase {
  QueryCapabilityProjection({
    CapabilityProjectionCase? capabilityProjectionCase,
    ForwardBandCase? forwardBandCase,
    CapabilityRoutingCase? capabilityRoutingCase,
  })  : _capabilityProjectionCase =
            capabilityProjectionCase ?? GetIt.I<CapabilityProjectionCase>(),
        _forwardBandCase = forwardBandCase ?? GetIt.I<ForwardBandCase>(),
        _capabilityRoutingCase =
            capabilityRoutingCase ?? GetIt.I<CapabilityRoutingCase>();

  final CapabilityProjectionCase _capabilityProjectionCase;
  final ForwardBandCase _forwardBandCase;
  final CapabilityRoutingCase _capabilityRoutingCase;

  static final _targetId = InputFieldString(fieldName: 'targetId');
  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _context = InputFieldString(fieldName: 'context');
  static final _slug = InputFieldString(fieldName: 'slug');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        subjectiveTags,
        forwardContext,
        tagExplanation,
        myRoutingTags,
      ];

  GraphQLObjectField<dynamic, dynamic> get subjectiveTags =>
      GraphQLObjectField(
        'subjectiveTags',
        GraphQLListType(gqlTypeTagProjection.nonNullable()),
        arguments: [_targetId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final rows = await _capabilityProjectionCase.subjectiveTags(
            actorId: jwt.sub,
            targetId: _targetId.fromArgsNonNullable(args),
          );
          return rows.map(_tagProjectionToGql).toList(growable: false);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get forwardContext =>
      GraphQLObjectField(
        'forwardContext',
        GraphQLListType(gqlTypeForwardBandRow.nonNullable()),
        arguments: [_beaconId.field, _context.fieldNullable],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final rows = await _forwardBandCase.forwardContext(
            actorId: jwt.sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
            rawContext: _context.fromArgs(args) ?? '',
          );
          return rows.map(_forwardBandRowToGql).toList(growable: false);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get tagExplanation =>
      GraphQLObjectField(
        'tagExplanation',
        graphQLString,
        arguments: [_targetId.field, _slug.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          return _capabilityProjectionCase.tagExplanation(
            actorId: jwt.sub,
            targetId: _targetId.fromArgsNonNullable(args),
            slug: _slug.fromArgsNonNullable(args),
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get myRoutingTags =>
      GraphQLObjectField(
        'myRoutingTags',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final muted = await _capabilityRoutingCase.myRoutingTags(
            actorId: jwt.sub,
          );
          return muted.toList(growable: false);
        },
      );

  static Map<String, dynamic> promptStateToGql(PromptState state) => {
        'inviterUserId': state.inviterUserId,
        'inviteeUserId': state.inviteeUserId,
        'state': state.state.name,
      };

  static Map<String, dynamic> _tagProjectionToGql(TagProjection row) => {
        'subjectUserId': row.subjectUserId,
        'tagSlug': row.tagSlug,
        'tier': row.tier.name,
      };

  static Map<String, dynamic> _forwardBandRowToGql(ForwardBandRow row) => {
        'userId': row.userId,
        'rowTier': row.rowTier?.name,
        'labels': row.labels.map(_tagProjectionToGql).toList(growable: false),
        'rank': row.rank,
        'isExploration': row.isExploration,
      };
}
