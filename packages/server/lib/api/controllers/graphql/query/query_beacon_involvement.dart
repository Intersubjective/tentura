import 'package:tentura_server/domain/use_case/beacon_involvement_case.dart';

import '../custom_types.dart';
import '../gql_node_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_v2_dto_maps.dart';

/// Root query field [beaconInvolvement]: authoritative involvement ids from Postgres.
///
/// Do not duplicate this data via Hasura `beacon.rejected_user_ids` on the same
/// `beacon_by_pk` selection — empty `SETOF text` results drop the parent beacon row.
final class QueryBeaconInvolvement extends GqlNodeBase {
  QueryBeaconInvolvement({BeaconInvolvementCase? beaconInvolvementCase})
    : _beaconInvolvementCase =
          beaconInvolvementCase ?? GetIt.I<BeaconInvolvementCase>();

  final BeaconInvolvementCase _beaconInvolvementCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconInvolvement,
    beaconInvolvements,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconInvolvement =>
      GraphQLObjectField(
        'beaconInvolvement',
        gqlTypeBeaconInvolvement.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final creds = getCredentials(args);
          return _beaconInvolvementCase
              .asMap(
                beaconId: InputFieldId.fromArgsNonNullable(args),
                currentUserId: creds.sub,
              )
              .then(beaconInvolvementResultToGqlMap);
        },
      );
  static final _ids = InputFieldStringList(fieldName: 'ids');

  /// Unknown and unreadable ids are omitted, never represented as empty data.
  GraphQLObjectField<dynamic, dynamic> get beaconInvolvements =>
      GraphQLObjectField(
        'beaconInvolvements',
        GraphQLListType(gqlTypeBeaconInvolvement.nonNullable()),
        arguments: [_ids.field],
        resolve: (_, args) async {
          final creds = getCredentials(args);
          final rows = await _beaconInvolvementCase.asBatch(
            beaconIds: _ids.fromArgsNonNullable(args),
            currentUserId: creds.sub,
          );
          return [
            for (final entry in rows.entries)
              {
                'beaconId': entry.key,
                ...beaconInvolvementResultToGqlMap(entry.value),
              },
          ];
        },
      );
}
