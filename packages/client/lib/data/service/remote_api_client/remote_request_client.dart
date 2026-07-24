import 'package:ferry/ferry.dart';

/// Narrow data-layer transport seam for repositories that issue GraphQL
/// operations.
// A one-operation interface is intentional: repositories must not depend on
// authentication or realtime lifecycle methods just to issue a request.
// ignore: one_member_abstracts
abstract interface class RemoteRequestClient {
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]);
}
