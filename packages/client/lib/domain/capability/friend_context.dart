import 'package:freezed_annotation/freezed_annotation.dart';

part 'friend_context.freezed.dart';

@freezed
abstract class FriendContext with _$FriendContext {
  const factory FriendContext({
    @Default(0) int activeForwardsToCount,
    @Default(0) int coInvolvedBeaconsCount,
  }) = _FriendContext;

  const FriendContext._();

  static const empty = FriendContext();
}
