import 'package:injectable/injectable.dart';

import '../entity/constellation_field_search_result.dart';
import '../port/constellation_field_search_port.dart';

@lazySingleton
final class ConstellationFieldSearchCase {
  ConstellationFieldSearchCase(this._port);

  final ConstellationFieldSearchPort _port;

  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  }) =>
      _port.search(query: query, context: context);
}
