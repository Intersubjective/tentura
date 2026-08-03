import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'blocked_users_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BlockedUsersState extends StateBase with _$BlockedUsersState {
  const factory BlockedUsersState({
    @Default([]) List<BlockIntent> blocks,
    @Default(StateIsSuccess()) StateStatus status,
    String? expandedOriginId,
    @Default([]) List<Profile> expandedInherited,
    @Default(false) bool expandedLoading,
  }) = _BlockedUsersState;

  const BlockedUsersState._();
}
