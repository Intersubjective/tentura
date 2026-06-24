import 'package:tentura_server/domain/entity/beacon_room_record.dart';

abstract class PollingRepositoryPort {
  Future<PollingVotePolicy?> findById(String pollingId);

  Future<String> createWithVariants({
    required String authorId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  });
}
