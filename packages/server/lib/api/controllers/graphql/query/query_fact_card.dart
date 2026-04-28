import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryFactCard extends GqlNodeBase {
  QueryFactCard({BeaconFactCardCase? beaconFactCardCase})
      : _case = beaconFactCardCase ?? GetIt.I<BeaconFactCardCase>();

  final BeaconFactCardCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconFactCardList];

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardList =>
      GraphQLObjectField(
        'BeaconFactCardList',
        GraphQLListType(gqlTypeBeaconFactCardRow.nonNullable()).nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.list(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
            ),
      );
}
