import 'package:tentura_server/domain/use_case/capability_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCapability extends GqlNodeBase {
  QueryCapability({CapabilityCase? capabilityCase})
    : _capabilityCase = capabilityCase ?? GetIt.I<CapabilityCase>();

  final CapabilityCase _capabilityCase;

  static final _subjectUserId = InputFieldString(fieldName: 'subjectUserId');
  static final _subjectUserIds = GraphQLFieldInput(
    'subjectUserIds',
    GraphQLListType(graphQLString.nonNullable()).nonNullable(),
  );
  static final _limit = GraphQLFieldInput('limit', graphQLInt);

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    myPrivateLabelsForUser,
    personCapabilityCues,
    personTopCapabilitiesBatch,
  ];

  GraphQLObjectField<dynamic, dynamic> get myPrivateLabelsForUser =>
      GraphQLObjectField(
        'myPrivateLabelsForUser',
        GraphQLListType(graphQLString.nonNullable()),
        arguments: [_subjectUserId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _capabilityCase.getPrivateLabelsForUser(
            observerId: jwt.sub,
            subjectId: _subjectUserId.fromArgsNonNullable(args),
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get personCapabilityCues =>
      GraphQLObjectField(
        'personCapabilityCues',
        gqlTypePersonCapabilityCuesPayload.nonNullable(),
        arguments: [_subjectUserId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final subjectId = _subjectUserId.fromArgsNonNullable(args);
          final cues = await _capabilityCase.getCapabilityCues(
            viewerId: jwt.sub,
            subjectId: subjectId,
          );
          final viewerVisible = await _capabilityCase.fetchViewerVisible(
            viewerId: jwt.sub,
            subjectId: subjectId,
          );
          return {
            'privateLabels': cues.privateLabels,
            'forwardReasonsByMe': cues.forwardReasonsByMe
                .map(
                  (e) => {
                    'slug': e.slug,
                    'count': e.count,
                    'lastSeenAt': e.lastSeenAt,
                  },
                )
                .toList(),
            'commitRoles': cues.commitRoles
                .map(
                  (e) => {
                    'slug': e.slug,
                    'beaconId': e.beaconId,
                    'beaconTitle': e.beaconTitle,
                    'createdAt': e.createdAt,
                  },
                )
                .toList(),
            'closeAckByMe': cues.closeAckByMe
                .map(
                  (e) => {
                    'slug': e.slug,
                    'beaconId': e.beaconId,
                    'beaconTitle': e.beaconTitle,
                    'createdAt': e.createdAt,
                  },
                )
                .toList(),
            'closeAckAboutMe': cues.closeAckAboutMe
                .map(
                  (e) => {
                    'slug': e.slug,
                    'beaconId': e.beaconId,
                    'beaconTitle': e.beaconTitle,
                    'createdAt': e.createdAt,
                  },
                )
                .toList(),
            'viewerVisible': viewerVisible
                .map((e) => {'slug': e.slug, 'hasManualLabel': e.hasManualLabel})
                .toList(),
          };
        },
      );

  GraphQLObjectField<dynamic, dynamic> get personTopCapabilitiesBatch =>
      GraphQLObjectField(
        'personTopCapabilitiesBatch',
        GraphQLListType(gqlTypePersonTopCapabilities.nonNullable()).nonNullable(),
        arguments: [_subjectUserIds, _limit],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final subjectIds =
              (args['subjectUserIds'] as List<dynamic>).cast<String>();
          final limit = (args['limit'] as int?) ?? 2;
          final result = await _capabilityCase.fetchTopCapabilitiesBatch(
            viewerId: jwt.sub,
            subjectIds: subjectIds,
            limit: limit,
          );
          return result.entries
              .map((e) => {'subjectId': e.key, 'slugs': e.value})
              .toList();
        },
      );
}
