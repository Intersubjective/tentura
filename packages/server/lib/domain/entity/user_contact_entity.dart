import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_contact_entity.freezed.dart';

/// What [viewerId] privately calls [subjectId] (subjective profiles).
/// Private to the viewer — the subject must never see it.
@freezed
abstract class UserContactEntity with _$UserContactEntity {
  const factory UserContactEntity({
    required String viewerId,
    required String subjectId,
    required String contactName,
    required DateTime updatedAt,
  }) = _UserContactEntity;

  const UserContactEntity._();

  /// GraphQL `myContacts` row (V2 direct path) — viewer id is implicit.
  Map<String, Object?> get asMap => {
    'subjectId': subjectId,
    'contactName': contactName,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
