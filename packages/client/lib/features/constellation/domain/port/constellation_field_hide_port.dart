import '../entity/constellation_field_hidden_item.dart';

abstract interface class ConstellationFieldHidePort {
  Future<void> hide({
    required int targetKind,
    required String targetId,
  });

  Future<void> unhide({
    required int targetKind,
    required String targetId,
  });

  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({String? cursor});
}
