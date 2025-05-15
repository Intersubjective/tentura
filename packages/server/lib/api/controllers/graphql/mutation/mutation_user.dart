import 'package:tentura_server/domain/use_case/user_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationUser extends GqlNodeBase {
  MutationUser({UserCase? userCase})
    : _userCase = userCase ?? GetIt.I<UserCase>();

  final UserCase _userCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    userUpdate,
    userDelete,
  ];

  GraphQLObjectField<dynamic, dynamic> get userUpdate => GraphQLObjectField(
    'userUpdate',
    gqlTypeProfile.nonNullable(),
    arguments: [
      InputFieldTitle.field,
      InputFieldDropImage.field,
      InputFieldDescription.field,
      InputFieldUpload.fieldImage,
    ],
    resolve:
        (_, args) => _userCase
            .updateProfile(
              id: getCredentials(args).sub,
              title: InputFieldTitle.fromArgs(args),
              description: InputFieldDescription.fromArgs(args),
              imageBytes: InputFieldUpload.fromArgs(args),
              dropImage: InputFieldDropImage.fromArgs(args),
            )
            .then((v) => v.asJson),
  );

  GraphQLObjectField<dynamic, dynamic> get userDelete => GraphQLObjectField(
    'userDelete',
    graphQLBoolean.nonNullable(),
    resolve: (_, args) => _userCase.deleteById(id: getCredentials(args).sub),
  );
}
