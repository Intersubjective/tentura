import '../entity/constellation_person_field_item.dart';

abstract interface class ConstellationPersonFieldItemsPort {
  Future<ConstellationPersonFieldItemsPage> fetch({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query,
    String? cursor,
  });
}
