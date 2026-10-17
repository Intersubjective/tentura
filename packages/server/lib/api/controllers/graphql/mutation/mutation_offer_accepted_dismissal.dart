import 'package:tentura_server/domain/use_case/offer_accepted_dismissal_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// B077b — the helper's × on the «Your help was accepted» sub-card, kept for
/// the whole account.
final class MutationOfferAcceptedDismissal extends GqlNodeBase {
  MutationOfferAcceptedDismissal({OfferAcceptedDismissalCase? useCase})
    : _case = useCase ?? GetIt.I<OfferAcceptedDismissalCase>();

  final OfferAcceptedDismissalCase _case;

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [dismissOfferAccepted];

  GraphQLObjectField<dynamic, dynamic> get dismissOfferAccepted =>
      GraphQLObjectField(
        'DismissOfferAccepted',
        gqlTypeOfferAcceptedDismissals.nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) => _case.dismiss(
          beaconId: _beaconId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );
}
