import 'package:logging/logging.dart';

import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

import '../service/remote_api_client/auth_loss_classifier.dart';
import '../service/remote_api_service.dart';

abstract class RemoteRepository {
  const RemoteRepository({
    required this.remoteApiService,
    required this.log,
  });

  final RemoteApiService remoteApiService;

  final Logger log;

  Future<TData> requestDataOnlineOrThrow<TData, TVars>(
    OperationRequest<TData, TVars> req, {
    String? label = 'No label',
  }) async {
    final response = await remoteApiService
        .request(req)
        .firstWhere((e) => e.dataSource == DataSource.Link);

    if (response.hasErrors) {
      if (response.linkException != null) {
        final linkError = response.linkException!;
        if (mapRemoteFailure(linkError) is! AuthSessionLostException) {
          log.severe('GraphQL link error', linkError);
        }
        throwClassifiedRemoteFailure(linkError);
      }
      if (response.graphqlErrors != null) {
        final gqlErrors = response.graphqlErrors!;
        if (mapRemoteFailure(gqlErrors) is! AuthSessionLostException) {
          log.severe('GraphQL errors', gqlErrors);
        }
        throwClassifiedRemoteFailure(gqlErrors);
      }
    }

    if (response.data == null) {
      throw const ServerNoDataException();
    } else {
      return response.data!;
    }
  }
}
