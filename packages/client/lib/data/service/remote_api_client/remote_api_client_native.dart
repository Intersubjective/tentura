import 'dart:async';
import 'dart:isolate';
import 'package:meta/meta.dart';
import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;
import 'package:ferry/ferry_isolate.dart';

import 'auth_box.dart';
import 'build_client.dart';
import 'credentials.dart';
import 'exception.dart';
import 'remote_api_client_base.dart';

class GetTokenRequest {}

typedef GetTokenResponse = ({Credentials? data, Object? error});

abstract base class RemoteApiClient extends RemoteApiClientBase {
  RemoteApiClient({
    required super.apiEndpointUrl,
    required super.authJwtExpiresIn,
    required super.requestTimeout,
    required super.userAgent,
  });

  IsolateClient? _gqlClient;

  SendPort? _replyPort;

  @override
  @mustCallSuper
  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  }) async {
    _gqlClient = await IsolateClient.create<ClientParams>(
      initClient,
      params: (
        apiEndpointUrl: apiEndpointUrl,
        requestTimeout: requestTimeout,
        userAgent: userAgent,
      ),
      messageHandler: (Object? message) async {
        switch (message) {
          case final GetTokenRequest _:
            try {
              _replyPort?.send((data: await getAuthToken(), error: null));
            } catch (e) {
              _replyPort?.send((data: null, error: e));
            }

          case final SendPort p:
            _replyPort = p;

          default:
        }
      },
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
    _replyPort = null;
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

  static Future<Client> initClient(
    ClientParams params,
    SendPort? sendPort,
  ) async {
    Credentials? credentials;
    final receivePort = ReceivePort();
    sendPort?.send(receivePort.sendPort);
    final tokenStream = receivePort
        .where((e) => e is GetTokenResponse)
        .cast<GetTokenResponse>()
        .asBroadcastStream();

    return buildClient(
      params: params,
      getToken: () async {
        if (credentials?.hasValidToken ?? false) {
          return credentials!.accessToken;
        } else {
          sendPort?.send(GetTokenRequest());
          final response = await tokenStream.first.timeout(
            params.requestTimeout,
          );
          if (response.data != null) {
            credentials = response.data;
            return credentials!.accessToken;
          } else {
            throw Exception(response.error);
          }
        }
      },
    );
  }
}
