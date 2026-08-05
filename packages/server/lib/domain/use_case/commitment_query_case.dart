import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class CommitmentQueryCase extends UseCaseBase {
  CommitmentQueryCase(
    this._commitmentRepository,
    this._helpOfferRepository, {
    required super.env,
    required super.logger,
  });

  final CommitmentRepositoryPort _commitmentRepository;
  final HelpOfferRepositoryPort _helpOfferRepository;

  Future<Set<String>> everAcknowledgedUserIds(String beaconId) async {
    final byUser = await _commitmentRepository.eventsByUser(beaconId);
    return {
      for (final entry in byUser.entries)
        if (everAcknowledged(entry.value)) entry.key,
    };
  }

  Future<Set<String>> currentCommitterUserIds(String beaconId) async {
    final byUser = await _commitmentRepository.eventsByUser(beaconId);
    final offers = await _helpOfferRepository.fetchAllByBeaconId(beaconId);
    final activeByUser = {
      for (final offer in offers)
        if (offer.isActive) offer.userId: true,
    };
    return {
      for (final entry in byUser.entries)
        if (hasCurrentStake(
          entry.value,
          hasActiveOffer: activeByUser[entry.key] ?? false,
        ))
          entry.key,
    };
  }

  Future<bool> everHadCommitter(String beaconId) async {
    final ids = await everAcknowledgedUserIds(beaconId);
    return ids.isNotEmpty;
  }

  Future<bool> everAcknowledgedPair({
    required String beaconId,
    required String userId,
  }) async {
    final events = await _commitmentRepository.eventsForPair(
      beaconId: beaconId,
      userId: userId,
    );
    return everAcknowledged(events);
  }
}
