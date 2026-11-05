import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'friends_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class FriendsState extends StateBase with _$FriendsState {
  const factory FriendsState({
    required Map<String, Profile> friends,
    @Default({}) Map<String, FriendContext> friendContexts,
    @Default({}) Map<String, PersonListMeta> listMeta,
    @Default({}) Map<String, PersonListMeta> optimisticListMeta,
    @Default(StateIsSuccess()) StateStatus status,
    Object? loadError,
    @Default(false) bool firstLoadDone,
  }) = _FriendsState;

  const FriendsState._();

  bool get hasError => loadError != null;
}
