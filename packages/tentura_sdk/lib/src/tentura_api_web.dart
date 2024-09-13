import 'dart:async';
import 'package:ferry/ferry.dart';
import 'package:gql_http_link/gql_http_link.dart';

import 'consts.dart';
import 'client/auth_link.dart';
import 'tentura_api_base.dart';

class TenturaApi extends TenturaApiBase {
  TenturaApi({
    required super.serverName,
    super.jwtExpiresIn,
    super.userAgent,
    super.storagePath,
  });

  late final Client _gqlClient;

  @override
  Future<void> init() async {
    _gqlClient = Client(
      link: Link.concat(
        AuthLink(() => getToken().then((v) => v.value)),
        HttpLink(
          Uri.https(
            serverName,
            pathGraphQLEndpoint,
          ).toString(),
          defaultHeaders: {
            'accept': 'application/json',
          },
        ),
      ),
      defaultFetchPolicies: {
        OperationType.query: FetchPolicy.NoCache,
      },
    );
  }

  @override
  Future<void> close() async {
    await _gqlClient.dispose();
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
            OperationRequest<TData, TVars>)?
        forward,
  ]) =>
      _gqlClient.request(request);

  @override
  Future<void> addRequestToRequestController<TData, TVars>(
    OperationRequest<TData, TVars> request,
  ) async =>
      _gqlClient.requestController.add(request);
}
