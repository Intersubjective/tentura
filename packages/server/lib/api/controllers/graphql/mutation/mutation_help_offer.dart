import 'package:tentura_server/domain/use_case/help_offer_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationHelpOffer extends GqlNodeBase {
  MutationHelpOffer({HelpOfferCase? helpOfferCase})
    : _helpOfferCase = helpOfferCase ?? GetIt.I<HelpOfferCase>();

  final HelpOfferCase _helpOfferCase;

  final _message = InputFieldString(fieldName: 'message');

  final _helpTypes = InputFieldStringList(fieldName: 'helpTypes');

  final _withdrawReason = InputFieldString(fieldName: 'withdrawReason');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [offerHelp, withdraw];

  GraphQLObjectField<dynamic, dynamic> get offerHelp => GraphQLObjectField(
    'beaconOfferHelp',
    graphQLBoolean.nonNullable(),
    arguments: [
      InputFieldId.field,
      _message.fieldNullable,
      _helpTypes.fieldNullable,
    ],
    resolve: (_, args) => _helpOfferCase
        .offerHelp(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          message: _message.fromArgs(args) ?? '',
          helpTypes: _helpTypes.fromArgs(args),
        )
        .then((_) => true),
  );

  GraphQLObjectField<dynamic, dynamic> get withdraw => GraphQLObjectField(
    'beaconWithdraw',
    graphQLBoolean.nonNullable(),
    arguments: [
      InputFieldId.field,
      _message.fieldNullable,
      _withdrawReason.field,
    ],
    resolve: (_, args) => _helpOfferCase
        .withdraw(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          message: _message.fromArgs(args) ?? '',
          withdrawReason: _withdrawReason.fromArgsNonNullable(args),
        )
        .then((_) => true),
  );
}
