import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/field_visibility_repository_port.dart';

@injectable
final class FieldVisibilityCase {
  const FieldVisibilityCase(this._repository);

  final FieldVisibilityRepositoryPort _repository;

  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  }) {
    if (targetId.trim().isEmpty) throw IdWrongException(id: targetId);
    return _repository.setHidden(
      viewerId: viewerId,
      targetKind: targetKind,
      targetId: targetId,
      hidden: hidden,
    );
  }

  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  }) => _repository.hiddenItems(viewerId: viewerId, before: before);
}
