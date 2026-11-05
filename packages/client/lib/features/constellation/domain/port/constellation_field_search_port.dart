import '../entity/constellation_field_search_result.dart';

// Single GraphQL operation; keep as its own injectable port (#255 l9k5.9).
// ignore: one_member_abstracts
abstract interface class ConstellationFieldSearchPort {
  Future<ConstellationFieldSearchResult> search({
    required String query,
    required String context,
  });
}
