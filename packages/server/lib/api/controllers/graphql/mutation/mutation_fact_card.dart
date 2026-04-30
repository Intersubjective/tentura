import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationFactCard extends GqlNodeBase {
  MutationFactCard({BeaconFactCardCase? beaconFactCardCase})
      : _case = beaconFactCardCase ?? GetIt.I<BeaconFactCardCase>();

  final BeaconFactCardCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _factCardId = InputFieldString(fieldName: 'factCardId');

  final _factText = InputFieldString(fieldName: 'factText');

  final GraphQLFieldInput<int, int> _visibility =
      GraphQLFieldInput('visibility', graphQLInt.nonNullable());

  final _newText = InputFieldString(fieldName: 'newText');

  final _sourceMessageId = InputFieldString(fieldName: 'sourceMessageId');

  List<GraphQLObjectField<dynamic, dynamic>> get all =>
      [
        beaconFactCardPin,
        beaconFactCardCorrect,
        beaconFactCardRemove,
        beaconFactCardSetVisibility,
      ];

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardSetVisibility =>
      GraphQLObjectField(
        'BeaconFactCardSetVisibility',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _factCardId.field,
          _visibility,
        ],
        resolve: (_, args) {
          final vis = args[_visibility.name]! as int;
          return _case.setVisibility(
            factCardId: _factCardId.fromArgsNonNullable(args),
            beaconId: _beaconIdStr.fromArgsNonNullable(args),
            actorUserId: getCredentials(args).sub,
            visibility: vis,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardPin =>
      GraphQLObjectField(
        'BeaconFactCardPin',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _factText.field,
          _visibility,
          _sourceMessageId.fieldNullable,
        ],
        resolve: (_, args) {
          final vis = args[_visibility.name]! as int;
          return _case.pin(
            beaconId: _beaconIdStr.fromArgsNonNullable(args),
            factText: _factText.fromArgsNonNullable(args),
            visibility: vis,
            userId: getCredentials(args).sub,
            sourceMessageId: _sourceMessageId.fromArgs(args),
          ).then((_) => true);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardCorrect =>
      GraphQLObjectField(
        'BeaconFactCardCorrect',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _factCardId.field,
          _newText.field,
        ],
        resolve: (_, args) => _case.correct(
              factCardId: _factCardId.fromArgsNonNullable(args),
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              actorUserId: getCredentials(args).sub,
              newText: _newText.fromArgsNonNullable(args),
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardRemove =>
      GraphQLObjectField(
        'BeaconFactCardRemove',
        graphQLBoolean.nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _factCardId.field,
        ],
        resolve: (_, args) => _case.remove(
              factCardId: _factCardId.fromArgsNonNullable(args),
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              actorUserId: getCredentials(args).sub,
            ),
      );
}
