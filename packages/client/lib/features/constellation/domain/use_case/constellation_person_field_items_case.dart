import 'package:injectable/injectable.dart';

import '../entity/constellation_person_field_item.dart';
import '../port/constellation_person_field_items_port.dart';

@lazySingleton
final class ConstellationPersonFieldItemsCase {
  ConstellationPersonFieldItemsCase(this._port);

  final ConstellationPersonFieldItemsPort _port;

  Future<ConstellationPersonFieldItemsPage> fetch({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query = '',
    String? cursor,
  }) =>
      _port.fetch(
        personId: personId,
        bucket: bucket,
        query: query,
        cursor: cursor,
      );
}
