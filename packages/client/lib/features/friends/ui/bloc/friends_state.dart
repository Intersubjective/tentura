import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'friends_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class FriendsState extends StateBase with _$FriendsState {
  const factory FriendsState({
    required Map<String, Profile> friends,
    @Default({}) Map<String, FriendContext> friendContexts,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _FriendsState;

  const FriendsState._();
}
