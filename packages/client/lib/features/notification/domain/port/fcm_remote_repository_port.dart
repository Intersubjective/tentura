abstract class FcmRemoteRepositoryPort {
  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  });
}
