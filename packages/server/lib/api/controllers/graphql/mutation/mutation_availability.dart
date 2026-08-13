import 'package:tentura_server/domain/use_case/user_availability_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationAvailability extends GqlNodeBase {
  MutationAvailability({UserAvailabilityCase? userAvailabilityCase})
    : _case = userAvailabilityCase ?? GetIt.I<UserAvailabilityCase>();

  final UserAvailabilityCase _case;

  static final _isLimited = InputFieldBool(fieldName: 'isLimited');
  static final _resumeOn = InputFieldCalendarDate(fieldName: 'resumeOn');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    userAvailabilitySetLimited,
    userAvailabilityPause,
    userAvailabilityResume,
  ];

  GraphQLObjectField<dynamic, dynamic> get userAvailabilitySetLimited =>
      GraphQLObjectField(
        'userAvailabilitySetLimited',
        graphQLBoolean.nonNullable(),
        arguments: [_isLimited.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          await _case.setLimited(
            userId: userId,
            isLimited: _isLimited.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get userAvailabilityPause =>
      GraphQLObjectField(
        'userAvailabilityPause',
        graphQLBoolean.nonNullable(),
        arguments: [_resumeOn.field],
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          await _case.pause(
            userId: userId,
            resumeOn: _resumeOn.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get userAvailabilityResume =>
      GraphQLObjectField(
        'userAvailabilityResume',
        graphQLBoolean.nonNullable(),
        resolve: (_, args) async {
          final userId = getCredentials(args).sub;
          await _case.resume(userId: userId);
          return true;
        },
      );
}
