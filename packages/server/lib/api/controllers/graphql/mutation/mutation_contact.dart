import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/contact_case.dart';
import 'package:tentura_server/domain/use_case/contact_check_case.dart';

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
  static final _kind = InputFieldString(fieldName: 'kind');
  static final _value = InputFieldString(fieldName: 'value');

  static final _checkResult = GraphQLObjectType('ContactCheckResult', null)
    ..fields.add(field('alreadyOnTentura', graphQLBoolean.nonNullable()));

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    contactSet,
    contactDelete,
    contactCheck,
  ];

  GraphQLObjectField<dynamic, dynamic> get contactCheck => GraphQLObjectField(
    'contactCheck',
    _checkResult.nonNullable(),
    arguments: [_kind.field, _value.field],
    resolve: (_, args) async {
      final caller = getCredentials(args).sub;
      if (_kind.fromArgsNonNullable(args) != ContactKind.email.wire) {
        throw const IdWrongException(description: 'Only email can be checked');
      }
      final matched = await GetIt.I<ContactCheckCase>().checkEmail(
        caller,
        _value.fromArgsNonNullable(args),
      );
      return {'alreadyOnTentura': matched};
    },
  );

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
