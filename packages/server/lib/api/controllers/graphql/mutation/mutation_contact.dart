import 'package:tentura_server/domain/use_case/contact_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Subjective profiles: per-viewer private contact names.
/// Viewer-scoped via JWT — the subject can never touch these rows.
final class MutationContact extends GqlNodeBase {
  MutationContact({ContactCase? contactCase})
    : _contactCase = contactCase ?? GetIt.I<ContactCase>();

  final ContactCase _contactCase;

  static final _subjectUserId = InputFieldString(fieldName: 'subjectUserId');

  static final _contactName = InputFieldString(fieldName: 'contactName');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    contactSet,
    contactDelete,
  ];

  GraphQLObjectField<dynamic, dynamic> get contactSet => GraphQLObjectField(
    'contactSet',
    graphQLBoolean.nonNullable(),
    arguments: [_subjectUserId.field, _contactName.field],
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      await _contactCase.set(
        viewerId: jwt.sub,
        subjectId: _subjectUserId.fromArgsNonNullable(args),
        contactName: _contactName.fromArgsNonNullable(args),
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get contactDelete => GraphQLObjectField(
    'contactDelete',
    graphQLBoolean.nonNullable(),
    arguments: [_subjectUserId.field],
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      return _contactCase.delete(
        viewerId: jwt.sub,
        subjectId: _subjectUserId.fromArgsNonNullable(args),
      );
    },
  );
}
