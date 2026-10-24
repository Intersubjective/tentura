import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationPeopleTags extends GqlNodeBase {
  MutationPeopleTags({PeopleTagsCase? useCase})
    : _case = useCase ?? GetIt.I<PeopleTagsCase>();

  final PeopleTagsCase _case;

  static final _id = InputFieldString(fieldName: 'id');
  static final _name = InputFieldString(fieldName: 'name');
  static final _glyph = InputFieldString(fieldName: 'glyph');
  static final _color = InputFieldInt(fieldName: 'color');
  static final _ord = InputFieldInt(fieldName: 'ord');
  static final _clientOpId = InputFieldString(fieldName: 'clientOpId');

  static final _ops = GraphQLFieldInput(
    'ops',
    _PersonTagMemberOpListType().nonNullable(),
  );

  static final _snapshot = GraphQLFieldInput(
    'snapshot',
    gqlInputPersonTagSnapshot.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    personTagCreate,
    personTagUpdate,
    personTagDelete,
    personTagRestore,
    personTagMembersApply,
  ];

  GraphQLObjectField<dynamic, dynamic> get personTagCreate =>
      GraphQLObjectField(
        'personTagCreate',
        gqlTypePersonTag.nonNullable(),
        arguments: [
          _name.field,
          _glyph.fieldNullable,
          _color.fieldNullable,
          _clientOpId.field,
        ],
        resolve: (_, args) async => (await _case.create(
          ownerId: getCredentials(args).sub,
          name: _name.fromArgsNonNullable(args),
          glyph: _glyph.fromArgs(args),
          color: _color.fromArgs(args),
          clientOpId: _clientOpId.fromArgsNonNullable(args),
        )).toGraphQL(),
      );

  GraphQLObjectField<dynamic, dynamic> get personTagUpdate =>
      GraphQLObjectField(
        'personTagUpdate',
        gqlTypePersonTag.nonNullable(),
        arguments: [
          _id.field,
          _name.fieldNullable,
          _glyph.fieldNullable,
          _color.fieldNullable,
          _ord.fieldNullable,
          _clientOpId.field,
        ],
        resolve: (_, args) async => (await _case.update(
          ownerId: getCredentials(args).sub,
          id: _id.fromArgsNonNullable(args),
          name: _name.fromArgs(args),
          glyph: _glyph.fromArgs(args),
          color: _color.fromArgs(args),
          ord: _ord.fromArgs(args),
          clientOpId: _clientOpId.fromArgsNonNullable(args),
        )).toGraphQL(),
      );

  GraphQLObjectField<dynamic, dynamic> get personTagDelete =>
      GraphQLObjectField(
        'personTagDelete',
        gqlTypePersonTagSnapshot.nonNullable(),
        arguments: [_id.field, _clientOpId.field],
        resolve: (_, args) async => (await _case.delete(
          ownerId: getCredentials(args).sub,
          id: _id.fromArgsNonNullable(args),
          clientOpId: _clientOpId.fromArgsNonNullable(args),
        )).toJson(),
      );

  GraphQLObjectField<dynamic, dynamic> get personTagRestore =>
      GraphQLObjectField(
        'personTagRestore',
        gqlTypePersonTag.nonNullable(),
        arguments: [_snapshot, _clientOpId.field],
        resolve: (_, args) async => (await _case.restore(
          ownerId: getCredentials(args).sub,
          snapshot: PersonTagSnapshot.fromJson(
            Map<String, dynamic>.from(args[_snapshot.name]! as Map),
          ),
          clientOpId: _clientOpId.fromArgsNonNullable(args),
        )).toGraphQL(),
      );

  GraphQLObjectField<dynamic, dynamic> get personTagMembersApply =>
      GraphQLObjectField(
        'personTagMembersApply',
        graphQLBoolean.nonNullable(),
        arguments: [_ops, _clientOpId.field],
        resolve: (_, args) async {
          await _case.applyMembers(
            ownerId: getCredentials(args).sub,
            ops: [
              for (final op in args[_ops.name]! as List)
                Map<String, dynamic>.from(op as Map),
            ],
            clientOpId: _clientOpId.fromArgsNonNullable(args),
          );
          return true;
        },
      );
}

/// `[PersonTagMemberOpInput!]` typed over `dynamic`, so a decoded
/// `List<dynamic>` of maps passes validation on executors that do not re-type
/// variable lists.
final class _PersonTagMemberOpListType
    extends GraphQLListType<dynamic, dynamic> {
  _PersonTagMemberOpListType() : super(gqlInputPersonTagMemberOp.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}
