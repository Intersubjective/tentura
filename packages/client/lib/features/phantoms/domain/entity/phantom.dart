import 'package:freezed_annotation/freezed_annotation.dart';

part 'phantom.freezed.dart';

enum PhantomPinState { pinned }

enum PhantomInviteState { none, live }

/// A private Field entry for someone who is not on Tentura yet.
@freezed
abstract class Phantom with _$Phantom {
  const factory Phantom({
    required String id,
    required String displayName,
    required bool hasPrivateAvatar,
    required List<String> ownTagIds,
    required PhantomInviteState inviteState,
    required DateTime createdAt,
    DateTime? inviteCreatedAt,
    String? emoji,
    PhantomPinState? pinState,
  }) = _Phantom;
}
