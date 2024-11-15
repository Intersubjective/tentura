import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'rating_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
class RatingState with _$RatingState, StateFetchMixin {
  const factory RatingState({
    @Default([]) List<Profile> items,
    @Default('') String context,
    @Default('') String searchFilter,
    @Default(false) bool isSortedByAsc,
    @Default(false) bool isSortedByEgo,
    @Default(FetchStatus.isSuccess) FetchStatus status,
    Object? error,
  }) = _RatingState;

  const RatingState._();

  RatingState setLoading() => copyWith(status: FetchStatus.isLoading);

  RatingState setError(Object error) => copyWith(
        status: FetchStatus.isFailure,
        error: error,
      );
}
