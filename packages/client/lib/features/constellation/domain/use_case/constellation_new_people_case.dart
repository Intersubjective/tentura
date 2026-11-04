import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../port/constellation_new_people_port.dart';
import 'constellation_field_store_case.dart';

@lazySingleton
final class ConstellationNewPeopleCase extends UseCaseBase {
  ConstellationNewPeopleCase(
    this._port,
    this._store, {
    required super.env,
    required super.logger,
  });

  final ConstellationNewPeoplePort _port;
  final ConstellationFieldStoreCase _store;

  /// Optimistically clears «new on your Field» and sends the mutation (#898).
  Future<void> acknowledgeOpened(Iterable<String> peerIds) async {
    final ids = peerIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    _store.applyAcknowledgedNew(ids);
    try {
      await _port.acknowledgeNew(ids);
    } on Object catch (error, stackTrace) {
      logger.warning(
        'constellationAcknowledgeNew failed',
        error,
        stackTrace,
      );
    }
  }
}
