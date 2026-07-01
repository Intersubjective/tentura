import 'package:tentura_server/domain/use_case/email_test_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class MutationDebug extends GqlNodeBase {
  MutationDebug([EmailTestCase? emailTestCase])
      : _emailTestCase = emailTestCase ?? GetIt.I<EmailTestCase>();

  final EmailTestCase _emailTestCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    sendTestEmail,
  ];

  GraphQLObjectField<dynamic, dynamic> get sendTestEmail =>
      GraphQLObjectField(
        'emailSendTest',
        gqlTypeEmailTestSendResult.nonNullable(),
        resolve: (_, args) => _emailTestCase.sendTestEmail(
          userId: getCredentials(args).sub,
        ),
      );
}
