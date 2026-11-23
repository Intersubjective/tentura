import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';

typedef SignupResult = ({String accountId, bool requestLapsed});

/// Remote auth API (implemented by `AuthRemoteRepository` in data layer).
abstract class AuthRemoteRepositoryPort {
  Future<SignupResult> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  });

  Future<String> signIn(String seed, {String? authAttemptId});

  Future<String> signInWithSession();

  Future<void> establishSessionFromBearer({String? authAttemptId});

  Future<void> sessionLogout();

  /// Best-effort HttpOnly session cookie clear (logout POST with credentials).
  Future<SessionCookieClearResult> clearSessionCookie();

  Future<void> signOut();
}
