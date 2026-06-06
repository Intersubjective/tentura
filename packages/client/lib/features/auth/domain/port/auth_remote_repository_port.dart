import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart'
    show AuthRemoteRepository;
import 'package:tentura/features/auth/domain/entity/session_cookie_clear_result.dart';

/// Remote auth API (implemented by [AuthRemoteRepository] in data layer).
abstract class AuthRemoteRepositoryPort {
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  });

  Future<String> signIn(String seed);

  Future<String> signInWithSession();

  Future<void> establishSessionFromBearer();

  Future<void> sessionLogout();

  /// Best-effort HttpOnly session cookie clear (logout POST with credentials).
  Future<SessionCookieClearResult> clearSessionCookie();

  Future<void> signOut();
}
