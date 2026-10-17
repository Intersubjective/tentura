import 'package:tentura_server/domain/use_case/offer_accepted_dismissal_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// B077b — the Requests on which the viewer dismissed the «Your help was
/// accepted» sub-card (any device of the account).
final class QueryOfferAcceptedDismissal extends GqlNodeBase {
  QueryOfferAcceptedDismissal({OfferAcceptedDismissalCase? useCase})
    : _case = useCase ?? GetIt.I<OfferAcceptedDismissalCase>();

  final OfferAcceptedDismissalCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    offerAcceptedDismissals,
  ];

  GraphQLObjectField<dynamic, dynamic> get offerAcceptedDismissals =>
      GraphQLObjectField(
        'offerAcceptedDismissals',
        gqlTypeOfferAcceptedDismissals.nonNullable(),
        resolve: (_, args) => _case.list(userId: getCredentials(args).sub),
      );
}
