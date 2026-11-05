import '../entity/constellation_field_search_result.dart';

abstract interface class ConstellationFieldSearchPort {
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  });
}
