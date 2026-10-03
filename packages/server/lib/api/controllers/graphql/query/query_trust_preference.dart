import 'package:tentura_server/domain/use_case/trust_preference_case.dart';

import '../gql_nodel_base.dart';

final class QueryTrustPreference extends GqlNodeBase {
  QueryTrustPreference({TrustPreferenceCase? useCase})
    : _case = useCase ?? GetIt.I<TrustPreferenceCase>();

  final TrustPreferenceCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [noisyWallEnabled];

  GraphQLObjectField<dynamic, dynamic> get noisyWallEnabled =>
      GraphQLObjectField(
        'noisyWallEnabled',
        graphQLBoolean.nonNullable(),
        resolve: (_, args) =>
            _case.noisyWallEnabled(actorId: getCredentials(args).sub),
      );
}
