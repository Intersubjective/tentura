import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;

import 'auth_box.dart';
import 'auth_loss_classifier.dart';
import 'build_client.dart';
import 'exception.dart';
import 'remote_api_client_base.dart';

abstract base class RemoteApiClient extends RemoteApiClientBase {
  RemoteApiClient({
    required super.apiEndpointUrl,
    required super.apiEndpointUrlV2,
    required super.authJwtExpiresIn,
    required super.requestTimeout,
    required super.userAgent,
  });

  Client? _gqlClient;

  @override
  @mustCallSuper
  Future<void> setSessionAuth() async {
    await _gqlClient?.dispose();
    _gqlClient = null;
    await super.setSessionAuth();
    _gqlClient = await buildClient(
      params: (
        apiEndpointUrl: apiEndpointUrl,
        apiEndpointUrlV2: apiEndpointUrlV2,
        userAgent: userAgent,
        requestTimeout: requestTimeout,
      ),
      getToken: () async => (await getAuthToken()).accessToken,
    );
  }

  @override
  @mustCallSuper
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    await _gqlClient?.dispose();
    _gqlClient = null;
    _gqlClient = await buildClient(
      params: (
        apiEndpointUrl: apiEndpointUrl,
        apiEndpointUrlV2: apiEndpointUrlV2,
        userAgent: userAgent,
        requestTimeout: requestTimeout,
      ),
      getToken: () async => (await getAuthToken()).accessToken,
    );
    return super.setAuth(
      seed: seed,
      authTokenFetcher: authTokenFetcher,
      returnAuthRequestToken: returnAuthRequestToken,
    );
  }

  @override
  @mustCallSuper
  Future<void> dropAuth() async {
    await _gqlClient?.dispose();
    _gqlClient = null;
    await super.dropAuth();
  }

  @override
  @mustCallSuper
  Future<void> close() async {
    await super.close();
    await _gqlClient?.dispose();
    _gqlClient = null;
  }

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) {
    final client = _gqlClient;
    if (client == null) {
      throw const AuthenticationNoKeyException();
    }
    final stream = client.request(request);
    if (kUnboundedGraphQLOperationNames.contains(
      request.operation.operationName,
    )) {
      return stream;
    }
    // Ferry's own typed-link stack (RequestControllerTypedLink et al.) sits
    // *above* our custom `link` chain, so an operation can in rare cases
    // never reach it — leaving [_TimeoutLink]'s cap unarmed and the caller
    // waiting forever. Bound every request here too, at the true outer edge,
    // so a stalled operation always fails instead of hanging indefinitely.
    return stream.timeout(
      requestTimeout,
      onTimeout: (sink) => sink.addError(
        mapRemoteFailure(
          TimeoutException('GraphQL request timed out', requestTimeout),
        ),
      ),
    );
  }
}
