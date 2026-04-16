// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class PollingActRepositoryPort {
  Future<void> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  });
}
