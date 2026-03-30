import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'forward_state.freezed.dart';

@freezed
abstract class ForwardState extends StateBase with _$ForwardState {
  const factory ForwardState({
    @Default('') String beaconId,
    @Default('') String context,
    @Default('') String note,
    @Default('') String searchQuery,
    @Default([]) List<Profile> candidates,
    @Default({}) Set<String> selectedIds,
    @Default({}) Set<String> rejectedUserIds,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ForwardState;

  const ForwardState._();

  List<Profile> get filteredCandidates {
    if (searchQuery.isEmpty) return candidates;
    final q = searchQuery.toLowerCase();
    return candidates
        .where((p) => p.title.toLowerCase().contains(q))
        .toList();
  }

  int get selectedCount => selectedIds.length;
}
