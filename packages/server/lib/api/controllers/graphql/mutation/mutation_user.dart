import 'package:tentura_server/domain/use_case/user_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationUser extends GqlNodeBase {
  MutationUser({UserCase? userCase})
    : _userCase = userCase ?? GetIt.I<UserCase>();

  final UserCase _userCase;

  final _handleField = InputFieldString(fieldName: 'handle');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [update, delete];

  GraphQLObjectField<dynamic, dynamic> get update => GraphQLObjectField(
    'userUpdate',
    gqlTypeProfile.nonNullable(),
    arguments: [
      InputFieldDisplayName.field,
      InputFieldDropImage.field,
      InputFieldDescription.field,
      InputFieldUpload.fieldImage,
      _handleField.fieldNullable,
    ],
    resolve:
        (_, args) => _userCase
            .updateProfile(
              id: getCredentials(args).sub,
              displayName: InputFieldDisplayName.fromArgs(args),
              description: InputFieldDescription.fromArgs(args),
              imageBytes: InputFieldUpload.fromArgs(args),
              dropImage: InputFieldDropImage.fromArgs(args),
              setHandle: args.containsKey('handle'),
              handle: _handleField.fromArgs(args),
            )
            .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get delete => GraphQLObjectField(
    'userDelete',
    graphQLBoolean.nonNullable(),
    resolve: (_, args) => _userCase.deleteById(id: getCredentials(args).sub),
  );
}
