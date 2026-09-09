import '../entity/constellation_field.dart';

abstract interface class ConstellationRepositoryPort {
  Future<ConstellationField> fetch();
}
