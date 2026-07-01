import 'package:tentura_server/domain/use_case/fcm_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationFcm extends GqlNodeBase {
  MutationFcm([FcmCase? fcmCase]) : _fcmCase = fcmCase ?? GetIt.I<FcmCase>();

  final FcmCase _fcmCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    registerFcmToken,
    deleteFcmToken,
    sendTestNotification,
  ];

  GraphQLObjectField<dynamic, dynamic> get registerFcmToken =>
      GraphQLObjectField(
        'fcmTokenRegister',
        graphQLBoolean.nonNullable(),
        arguments: [
          _appIdInput.field,
          _tokenInput.field,
          _platformInput.field,
        ],
        resolve: (_, args) => _fcmCase.registerToken(
          userId: getCredentials(args).sub,
          appId: _appIdInput.fromArgsNonNullable(args),
          token: _tokenInput.fromArgsNonNullable(args),
          platform: _platformInput.fromArgsNonNullable(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get deleteFcmToken =>
      GraphQLObjectField(
        'fcmTokenDelete',
        graphQLBoolean.nonNullable(),
        arguments: [
          _appIdInput.field,
        ],
        resolve: (_, args) => _fcmCase.deleteToken(
          userId: getCredentials(args).sub,
          appId: _appIdInput.fromArgsNonNullable(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get sendTestNotification =>
      GraphQLObjectField(
        'fcmSendTestNotification',
        gqlTypeFcmTestSendResult.nonNullable(),
        resolve: (_, args) => _fcmCase.sendTestNotification(
          userId: getCredentials(args).sub,
        ),
      );

  static final _appIdInput = InputFieldString(fieldName: 'appId');

  static final _tokenInput = InputFieldString(fieldName: 'token');

  static final _platformInput = InputFieldString(fieldName: 'platform');
}
