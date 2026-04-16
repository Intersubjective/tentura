abstract class PollingActRepositoryPort {
  Future<void> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  });
}
