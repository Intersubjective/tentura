import 'package:tentura/features/auth/data/repository/auth_remote_repository.dart' show AuthRemoteRepository;

/// Remote auth API (implemented by [AuthRemoteRepository] in data layer).
abstract class AuthRemoteRepositoryPort {
  Future<String> signUp({
    required String seed,
    required String displayName,
    required String invitationCode,
    String? handle,
  });

  Future<String> signIn(String seed);

  Future<void> signOut();
}
