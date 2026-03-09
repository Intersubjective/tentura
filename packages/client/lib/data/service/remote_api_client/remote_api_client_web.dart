import 'dart:async';
import 'package:meta/meta.dart';
import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;

import 'auth_box.dart';
import 'build_client.dart';
import 'exception.dart';
import 'remote_api_client_base.dart';

abstract base class RemoteApiClient extends RemoteApiClientBase {
  RemoteApiClient({
    required super.apiEndpointUrl,
    required super.authJwtExpiresIn,
    required super.requestTimeout,
    required super.userAgent,
  });

  Client? _gqlClient;

  @override
  @mustCallSuper
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    _gqlClient = await buildClient(
      params: (
        apiEndpointUrl: apiEndpointUrl,
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
  ]) =>
      _gqlClient?.request(request) ??
      (throw const AuthenticationNoKeyException());
}
