import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/polling_act_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: PollingActRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class PollingActRepository implements PollingActRepositoryPort {
  const PollingActRepository(this._database);

  final TenturaDb _database;

  Future<void> create({
    required String authorId,
    required String pollingId,
    required String variantId,
  }) => _database.managers.pollingActs.create(
    (o) => o(
      authorId: authorId,
      pollingId: pollingId,
      pollingVariantId: variantId,
    ),
  );
}
