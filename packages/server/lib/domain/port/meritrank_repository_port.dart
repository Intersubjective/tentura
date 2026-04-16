abstract class MeritrankRepositoryPort {
  Future<int> init();

  Future<void> reset();

  Future<void> calculate({
    bool isBlocking = true,
    Duration timeout = const Duration(minutes: 10),
  });

  Future<void> putEdge({
    required String nodeA,
    required String nodeB,
    double weight = 1.0,
    String context = '',
    int ticker = 0,
  });

  Future<void> deleteEdge({
    required String nodeA,
    required String nodeB,
    String context = '',
  });
}
