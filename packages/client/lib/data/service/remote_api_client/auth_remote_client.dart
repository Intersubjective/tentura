import 'package:ferry/ferry.dart';

import 'auth_box.dart';
import 'credentials.dart';

/// Narrow data-layer seam used by the auth repository.
///
/// Keeping the transport behind this contract makes post-auth realtime binding
/// directly testable without substituting the application's final API client.
abstract interface class AuthRemoteClient {
  bool get isSessionAuth;
  bool get hasValidToken;

  Future<String?> setAuth({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
    AuthRequestIntent? returnAuthRequestToken,
  });

  Future<void> setSessionAuth();
  Future<void> dropAuth();
  Future<Credentials> getAuthToken();
  Future<void> bindRealtimeAccount(String accountId);
  Future<void> establishSessionFromBearer({String? authAttemptId});
  Future<void> sessionLogout();
  Future<bool> clearSessionCookie();

  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]);
}
