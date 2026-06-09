import 'package:logging/logging.dart';

import 'package:tentura/domain/exception/server_exception.dart';

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
        log.severe(response.linkException);
        throwClassifiedRemoteFailure(response.linkException);
      }
      if (response.graphqlErrors != null) {
        log.severe(response.graphqlErrors);
        throwClassifiedRemoteFailure(response.graphqlErrors);
      }
    }

    if (response.data == null) {
      throw const ServerNoDataException();
    } else {
      return response.data!;
    }
  }
}
