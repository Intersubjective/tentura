import 'package:tentura_server/domain/port/email_discoverability_port.dart';

import 'gql_nodel_base.dart';
import 'input/_input_types.dart';

final class EmailDiscoverabilityFields extends GqlNodeBase {
  const EmailDiscoverabilityFields();

  static final _enabled = InputFieldBool(fieldName: 'enabled');

  GraphQLObjectField<dynamic, dynamic> get read => GraphQLObjectField(
    'emailDiscoverability',
    graphQLBoolean.nonNullable(),
    description:
        'Whether people who have your email can see you are on Tentura.',
    resolve: (_, args) {
      final userId = getCredentials(args).sub;
      return GetIt.I<EmailDiscoverabilityPort>().getForAccount(userId);
    },
  );

  GraphQLObjectField<dynamic, dynamic> get set => GraphQLObjectField(
    'emailDiscoverabilitySet',
    graphQLBoolean.nonNullable(),
    description:
        'Set whether people who have your email can see you are on Tentura.',
    arguments: [_enabled.field],
    resolve: (_, args) {
      final userId = getCredentials(args).sub;
      return GetIt.I<EmailDiscoverabilityPort>().setForAccount(
        userId: userId,
        enabled: _enabled.fromArgsNonNullable(args),
      );
    },
  );
}
