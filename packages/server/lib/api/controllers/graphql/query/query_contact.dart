import 'package:tentura_server/domain/use_case/contact_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

/// Subjective profiles: the viewer's full private contact map.
final class QueryContact extends GqlNodeBase {
  QueryContact({ContactCase? contactCase})
    : _contactCase = contactCase ?? GetIt.I<ContactCase>();

  final ContactCase _contactCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    myContacts,
  ];

  GraphQLObjectField<dynamic, dynamic> get myContacts => GraphQLObjectField(
    'myContacts',
    GraphQLListType(gqlTypeUserContact.nonNullable()),
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      final contacts = await _contactCase.fetchMine(viewerId: jwt.sub);
      return [for (final contact in contacts) contact.asMap];
    },
  );
}
