import 'package:tentura/domain/entity/beacon_fact_history_entry.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'fact_history_state.freezed.dart';

@freezed
abstract class FactHistoryState extends StateBase with _$FactHistoryState {
  const factory FactHistoryState({
    @Default([]) List<BeaconFactTimelineEntry> entries,
    String? nextCursor,
    @Default(StateIsSuccess()) StateStatus status,
    Object? loadError,
  }) = _FactHistoryState;

  const FactHistoryState._();
}
