import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/repository/commitment_repository.dart';

@Singleton(order: 2)
class CommitmentCase {
  const CommitmentCase(this._commitmentRepository);

  final CommitmentRepository _commitmentRepository;

  Future<void> commit({
    required String beaconId,
    required String userId,
    String message = '',
  }) => _commitmentRepository.upsert(
    beaconId: beaconId,
    userId: userId,
    message: message,
  );

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    String message = '',
  }) => _commitmentRepository.withdraw(
    beaconId: beaconId,
    userId: userId,
    message: message,
  );
}
