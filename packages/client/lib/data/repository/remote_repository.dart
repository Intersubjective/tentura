import 'package:logging/logging.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';

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
        // TBD: check specific link exceptions
        throw const ConnectionUplinkException();
      }
      if (response.graphqlErrors != null) {
        log.severe(response.graphqlErrors);
        // TBD: parse specific server codes
        throw const ServerUnknownException();
      }
    }

    if (response.data == null) {
      throw const ServerNoDataException();
    } else {
      return response.data!;
    }
  }
}
