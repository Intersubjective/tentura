import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_involvement_read_port.dart';

import '../database/tentura_db.dart';
import 'forward_edge_repository.dart';
import 'help_offer_repository.dart';
import 'help_offer_admission_repository.dart';
import 'inbox_repository.dart';

@LazySingleton(as: BeaconInvolvementReadPort)
class BeaconInvolvementReadRepository implements BeaconInvolvementReadPort {
  const BeaconInvolvementReadRepository(this._db);

  final TenturaDb _db;

  @override
  int get maxBatchSize => 50;

  @override
  Future<Map<String, BeaconInvolvementRecords>> fetchReadableBatch({
    required List<String> beaconIds,
    required String viewerId,
  }) => _db.withReadSnapshot(() async {
    final readable = await _db
        .customSelect(
          r'SELECT id FROM unnest($1::text[]) AS id '
          r'WHERE public.beacon_can_read_involvement(id, $2)',
          variables: [
            Variable<List<String>>(beaconIds, PgTypes.textArray),
            Variable<String>(viewerId),
          ],
        )
        .get();
    final ids = readable.map((row) => row.read<String>('id')).toSet();
    if (ids.isEmpty) return {};

    // Stateless adapters share this snapshot's executor and existing mappers.
    final edges = await ForwardEdgeRepository(_db).fetchByBeaconIds(ids);
    final offers = await HelpOfferRepository(_db).fetchAllByBeaconIds(ids);
    final admissions = await HelpOfferAdmissionRepository(
      _db,
    ).latestForBeacons(ids);
    final inbox = await InboxRepository(_db).fetchInvolvementByBeaconIds(ids);
    return {
      for (final id in ids)
        id: (
          edges: edges.where((edge) => edge.beaconId == id).toList(),
          helpOffers: offers.where((offer) => offer.beaconId == id).toList(),
          latestAdmissions: {
            for (final event in admissions)
              if (event.beaconId == id) event.offerUserId: event,
          },
          rejectedIds: inbox
              .where((item) => item.beaconId == id && item.status == 2)
              .map((item) => item.userId)
              .toList(),
          watchingIds: inbox
              .where((item) => item.beaconId == id && item.status == 1)
              .map((item) => item.userId)
              .toList(),
          onwardForwarderIds: edges
              .where((edge) => edge.beaconId == id)
              .map((edge) => edge.senderId)
              .toSet()
              .toList(),
        ),
    };
  });
}
