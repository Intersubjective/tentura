import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/use_case/field_visibility_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationFieldVisibility extends GqlNodeBase {
  MutationFieldVisibility({FieldVisibilityCase? useCase})
    : _case = useCase ?? GetIt.I<FieldVisibilityCase>();

  final FieldVisibilityCase _case;
  static final _kind = InputFieldInt(fieldName: 'targetKind');
  static final _id = InputFieldString(fieldName: 'targetId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    _mutation('fieldHide', true),
    _mutation('fieldUnhide', false),
  ];

  GraphQLObjectField<dynamic, dynamic> _mutation(String name, bool hidden) =>
      GraphQLObjectField(
        name,
        graphQLBoolean.nonNullable(),
        arguments: [_kind.fieldNonNullable, _id.field],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          await _case.setHidden(
            viewerId: viewerId,
            targetKind: FieldTargetKind.parse(_kind.fromArgsNonNullable(args)),
            targetId: _id.fromArgsNonNullable(args),
            hidden: hidden,
          );
          return true;
        },
      );
}
