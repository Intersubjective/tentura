import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/profile.dart';

part 'graph_person_context_state.freezed.dart';

@freezed
abstract class GraphPersonContextState with _$GraphPersonContextState {
  const factory GraphPersonContextState({
    Profile? selectedProfile,
    String? dismissedFocusId,
    @Default(false) bool trustLoading,
    Object? trustError,
    @Default(0) int selectionSequence,
  }) = _GraphPersonContextState;
}
