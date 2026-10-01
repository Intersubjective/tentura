import 'package:freezed_annotation/freezed_annotation.dart';

part 'closure_member.freezed.dart';

@freezed
abstract class ClosureMember with _$ClosureMember {
  const factory ClosureMember({
    required String id,
    @Default(false) bool notInRequest,
    String? displayName,
    String? avatarId,
    List<String>? helpTypes,
    String? offerText,

    /// Author only: `voluntary` | `removed`.
    String? departure,
  }) = _ClosureMember;

  const ClosureMember._();
}
