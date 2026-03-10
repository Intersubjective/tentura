import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'rating_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class RatingState extends StateBase with _$RatingState {
  const factory RatingState({
    @Default('') String context,
    @Default([]) List<Profile> items,
    @Default('') String searchFilter,
    @Default(false) bool isSortedByAsc,
    @Default(false) bool isSortedByReverse,
    @Default(false) bool isSortedByAlter,
    @Default(false) bool isSortedByClass,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _RatingState;

  const RatingState._();
}
