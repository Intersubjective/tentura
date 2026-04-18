import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/beacon_update_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_update_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconUpdateCase extends UseCaseBase {
  BeaconUpdateCase(
    this._beaconRepository,
    this._beaconUpdateRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;

  final BeaconUpdateRepositoryPort _beaconUpdateRepository;

  Future<BeaconUpdateEntity> post({
    required String userId,
    required String beaconId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Update content is required');
    }
    if (trimmed.length > kDescriptionMaxLength) {
      throw const BeaconCreateException(description: 'Update content is too long');
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (beacon.author.id != userId) {
      throw const UnauthorizedException(
        description: 'Only the beacon author can post updates',
      );
    }
    if (!beacon.isActive) {
      throw const BeaconCreateException(
        description: 'Beacon is not open for updates',
      );
    }
    return _beaconUpdateRepository.createUpdate(
      beaconId: beaconId,
      authorId: userId,
      content: trimmed,
    );
  }

  Future<BeaconUpdateEntity> edit({
    required String userId,
    required String id,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Update content is required');
    }
    if (trimmed.length > kDescriptionMaxLength) {
      throw const BeaconCreateException(description: 'Update content is too long');
    }
    final existing = await _beaconUpdateRepository.getById(id);
    if (existing == null) {
      throw IdNotFoundException(id: id, description: 'Beacon update not found');
    }
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: existing.beaconId,
    );
    if (beacon.author.id != userId) {
      throw const UnauthorizedException(
        description: 'Only the beacon author can edit updates',
      );
    }
    if (!beacon.isActive) {
      throw const BeaconCreateException(
        description: 'Beacon is not open for updates',
      );
    }
    return _beaconUpdateRepository.editUpdate(
      id: id,
      authorId: userId,
      content: trimmed,
    );
  }
}
