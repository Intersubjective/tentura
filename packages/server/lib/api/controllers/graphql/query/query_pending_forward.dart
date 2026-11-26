import 'package:tentura_server/domain/use_case/phantom_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryPendingForward extends GqlNodeBase {
  const QueryPendingForward();

  static final _beaconId = InputFieldString(fieldName: 'beaconId');
  static final _type = GraphQLObjectType('PendingForward', null)
    ..fields.addAll([
      for (final name in [
        'id',
        'phantomId',
        'senderId',
        'beaconId',
        'displayName',
        'state',
      ])
        field(name, graphQLString.nonNullable()),
    ]);

  GraphQLObjectField<dynamic, dynamic> get fieldForRequest =>
      GraphQLObjectField(
        'beaconPendingForwards',
        GraphQLListType(_type.nonNullable()),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final rows = await GetIt.I<PhantomCase>().pendingForRequest(
            senderId: getCredentials(args).sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
          );
          return [
            for (final row in rows)
              {
                'id': row.id,
                'phantomId': row.phantomId,
                'senderId': row.senderId,
                'beaconId': row.beaconId,
                'displayName': row.displayName,
                'state': row.state.name,
              },
          ];
        },
      );
}
