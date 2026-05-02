import 'package:tentura_server/domain/port/person_capability_event_repository_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryForwardReasons extends GqlNodeBase {
  QueryForwardReasons({PersonCapabilityEventRepositoryPort? repository})
    : _repository = repository ?? GetIt.I<PersonCapabilityEventRepositoryPort>();

  final PersonCapabilityEventRepositoryPort _repository;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [forwardReasonsByBeacon];

  GraphQLObjectField<dynamic, dynamic> get forwardReasonsByBeacon =>
      GraphQLObjectField(
        'forwardReasonsByBeacon',
        GraphQLListType(gqlTypeForwardReasonRow.nonNullable()).nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) async {
          final creds = getCredentials(args);
          final rows = await _repository.fetchForwardReasonsByBeaconId(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            viewerId: creds.sub,
          );
          return rows
              .map(
                (r) => {
                  'senderId': r.observerId,
                  'recipientId': r.subjectId,
                  'slugs': r.slugs,
                },
              )
              .toList();
        },
      );
}
