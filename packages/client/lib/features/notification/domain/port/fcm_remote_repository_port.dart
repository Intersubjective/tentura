// ignore: one_member_abstracts -- injectable port with a single remote call
abstract class FcmRemoteRepositoryPort {
  Future<void> registerToken({
    required String appId,
    required String token,
    required String platform,
  });
}
