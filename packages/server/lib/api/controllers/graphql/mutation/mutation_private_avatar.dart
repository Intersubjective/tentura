import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/private_avatar_repository_port.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../input/person_subject_input.dart';

final class MutationPrivateAvatar extends GqlNodeBase {
  const MutationPrivateAvatar();

  GraphQLObjectField<dynamic, dynamic> get upload => GraphQLObjectField(
    'personPrivateAvatarUpload',
    graphQLBoolean.nonNullable(),
    arguments: [...PersonSubjectInput.arguments, InputFieldUpload.field],
    resolve: (_, args) async {
      final ownerId = getCredentials(args).sub;
      final subject = PersonSubjectInput.fromArgs(args, purpose: 'the avatar');
      final bytes = InputFieldUpload.fromArgs(args);
      if (bytes == null) {
        throw const IdWrongException(description: 'Choose a JPEG to upload');
      }
      await GetIt.I<PrivateAvatarRepositoryPort>().put(
        ownerId: ownerId,
        subject: subject,
        bytes: bytes,
      );
      return true;
    },
  );
}
