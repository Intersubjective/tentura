import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/saved_fact_repository_port.dart';

import '_use_case_base.dart';

/// Plan §5.4 Save / Unsave: a user's personal list of fact pointers.
@Singleton(order: 2)
final class SavedFactCase extends UseCaseBase {
  SavedFactCase(
    this._facts,
    this._saved, {
    required super.env,
    required super.logger,
  });

  final BeaconFactCardRepositoryPort _facts;

  final SavedFactRepositoryPort _saved;

  /// Saves [factCardId] of [beaconId] for [userId]. Throws
  /// [FactCopySourceUnavailableException] unless it is a live fact of
  /// [beaconId] the user may read, and [SavedFactLimitException] when a new
  /// row would pass [kSavedFactCap]. Saving twice is not an error.
  Future<bool> save({
    required String beaconId,
    required String factCardId,
    required String userId,
  }) async {
    final access = await _facts.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    final ref = access.exists && access.canReadContent
        ? await _facts.loadOriginRef(factCardId: factCardId, beaconId: beaconId)
        : null;
    if (ref == null ||
        !access.canReadFact(status: ref.status, visibility: ref.visibility)) {
      throw const FactCopySourceUnavailableException();
    }
    if (!await _saved.save(
      userId: userId,
      factCardId: factCardId,
      cap: kSavedFactCap,
    )) {
      throw const SavedFactLimitException();
    }
    return true;
  }

  /// Removes [factCardId] from the saved facts of [userId]. No access check:
  /// a user can always drop their own row, even for an unavailable fact.
  Future<bool> unsave({
    required String factCardId,
    required String userId,
  }) async {
    await _saved.unsave(userId: userId, factCardId: factCardId);
    return true;
  }
}
