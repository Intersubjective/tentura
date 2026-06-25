import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/forward_graph_focus_rules.dart';

part 'graph_state.freezed.dart';

@freezed
abstract class GraphState extends StateBase with _$GraphState {
  const factory GraphState({
    required Profile me,
    required String focus,
    @Default('') String context,
    @Default(true) bool isAnimated,
    @Default(true) bool positiveOnly,
    ForwardsGraphViewerRole? helpOffererViewerRole,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _GraphState;

  const GraphState._();
}
