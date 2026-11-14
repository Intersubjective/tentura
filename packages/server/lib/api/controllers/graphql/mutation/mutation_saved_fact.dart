import 'package:tentura_server/domain/use_case/saved_fact_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationSavedFact extends GqlNodeBase {
  MutationSavedFact({SavedFactCase? savedFactCase})
    : _case = savedFactCase ?? GetIt.I<SavedFactCase>();

  final SavedFactCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _factCardId = InputFieldString(fieldName: 'factCardId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconFactCardSave,
    beaconFactCardUnsave,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardSave =>
      GraphQLObjectField(
        'BeaconFactCardSave',
        graphQLBoolean.nonNullable(),
        arguments: [_beaconIdStr.field, _factCardId.field],
        resolve: (_, args) => _case.save(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          factCardId: _factCardId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardUnsave =>
      GraphQLObjectField(
        'BeaconFactCardUnsave',
        graphQLBoolean.nonNullable(),
        arguments: [_factCardId.field],
        resolve: (_, args) => _case.unsave(
          factCardId: _factCardId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );
}
