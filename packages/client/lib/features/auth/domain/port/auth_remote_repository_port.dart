/// Remote auth API (implemented by [AuthRemoteRepository] in data layer).
abstract class AuthRemoteRepositoryPort {
  Future<String> signUp({
    required String seed,
    required String title,
    required String invitationCode,
  });

  Future<String> signIn(String seed);

  Future<void> signOut();
}
