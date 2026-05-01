import 'package:tentura_server/domain/use_case/capability_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCapability extends GqlNodeBase {
  QueryCapability({CapabilityCase? capabilityCase})
    : _capabilityCase = capabilityCase ?? GetIt.I<CapabilityCase>();

  final CapabilityCase _capabilityCase;

  static final _subjectUserId = InputFieldString(fieldName: 'subjectUserId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    myPrivateLabelsForUser,
    personCapabilityCues,
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
          final cues = await _capabilityCase.getCapabilityCues(
            viewerId: jwt.sub,
            subjectId: _subjectUserId.fromArgsNonNullable(args),
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
          };
        },
      );
}
