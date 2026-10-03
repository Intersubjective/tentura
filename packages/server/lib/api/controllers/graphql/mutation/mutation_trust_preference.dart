import 'package:tentura_server/domain/use_case/trust_preference_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationTrustPreference extends GqlNodeBase {
  MutationTrustPreference({TrustPreferenceCase? useCase})
    : _case = useCase ?? GetIt.I<TrustPreferenceCase>();

  final TrustPreferenceCase _case;

  static final _enabled = InputFieldBool(fieldName: 'enabled');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [setNoisyWallEnabled];

  GraphQLObjectField<dynamic, dynamic> get setNoisyWallEnabled =>
      GraphQLObjectField(
        'setNoisyWallEnabled',
        graphQLBoolean.nonNullable(),
        arguments: [_enabled.field],
        resolve: (_, args) => _case.setNoisyWallEnabled(
          actorId: getCredentials(args).sub,
          enabled: _enabled.fromArgsNonNullable(args),
        ),
      );
}
