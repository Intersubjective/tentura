import 'auth_box.dart';
import 'credentials.dart';
import 'remote_request_client.dart';

/// Data-layer transport seam for authentication and realtime lifecycle work.
///
/// The auth repository also issues GraphQL operations, so this extends the
/// request-only contract used by ordinary repositories.
abstract interface class AuthRemoteClient implements RemoteRequestClient {
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
}
