import 'package:tentura_server/domain/entity/field_hidden_item.dart';

abstract class FieldVisibilityRepositoryPort {
  /// Checks target readability and changes only [viewerId]'s row atomically.
  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  });

  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  });
}
