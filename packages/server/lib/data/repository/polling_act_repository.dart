import 'package:injectable/injectable.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class PollingActRepository {
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
