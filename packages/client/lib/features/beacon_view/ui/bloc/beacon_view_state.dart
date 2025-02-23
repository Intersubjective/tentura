import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/comment.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_view_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
class BeaconViewState extends StateBase with _$BeaconViewState {
  const factory BeaconViewState({
    required Beacon beacon,
    @Default('') String focusCommentId,
    @Default(false) bool hasReachedMax,
    @Default([]) List<Comment> comments,
    @Default(Profile()) Profile myProfile,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconViewState;

  const BeaconViewState._();

  bool get hasNotReachedMax => !hasReachedMax;

  bool get isBeaconMine => beacon.author.id == myProfile.id;
  bool get isBeaconNotMine => beacon.author.id != myProfile.id;

  bool get hasFocusedComment => focusCommentId.isNotEmpty;
  bool get hasNoFocusedComment => focusCommentId.isEmpty;

  bool checkIfCommentIsMine(Comment comment) =>
      comment.author.id == myProfile.id;

  bool checkIfCommentIsNotMine(Comment comment) =>
      comment.author.id != myProfile.id;
}
