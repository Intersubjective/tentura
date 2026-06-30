import 'package:ferry/ferry.dart' as gql show ServerException;
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
        _failFromRemote(
          response.linkException!,
          kind: 'link error',
          label: label,
        );
      }
      if (response.graphqlErrors != null) {
        _failFromRemote(
          response.graphqlErrors!,
          kind: 'errors',
          label: label,
        );
      }
    }

    if (response.data == null) {
      throw const ServerNoDataException();
    } else {
      return response.data!;
    }
  }

  Never _failFromRemote(
    Object raw, {
    required String kind,
    required String? label,
  }) {
    final mapped = mapRemoteFailure(raw);
    if (mapped is! AuthSessionLostException) {
      final effectiveLabel = label == null || label.isEmpty
          ? 'No label'
          : label;
      log.warning('[$effectiveLabel] GraphQL $kind: $mapped');
    }

    final failure = _failureException(mapped);
    final stackTrace = _stackTraceFromRaw(raw);
    if (stackTrace != null) {
      Error.throwWithStackTrace(failure, stackTrace);
    }
    throw failure;
  }

  Exception _failureException(Object mapped) =>
      mapped is Exception ? mapped : Exception(mapped.toString());

  StackTrace? _stackTraceFromRaw(Object raw) {
    if (raw is gql.ServerException) {
      final originalStackTrace = raw.originalStackTrace;
      if (originalStackTrace is StackTrace) {
        return originalStackTrace;
      }
    }
    return null;
  }
}
