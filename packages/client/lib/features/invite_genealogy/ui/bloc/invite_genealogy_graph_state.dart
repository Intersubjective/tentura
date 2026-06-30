import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/ui/bloc/state_base.dart';

part 'invite_genealogy_graph_state.freezed.dart';

@freezed
abstract class InviteGenealogyGraphState extends StateBase
    with _$InviteGenealogyGraphState {
  const factory InviteGenealogyGraphState({
    @Default(StateIsSuccess()) StateStatus status,
    @Default('') String viewerNodeKey,
    @Default('') String targetNodeKey,
    @Default('') String commonAncestorNodeKey,
    @Default(<String>[]) List<String> nodeKeys,
  }) = _InviteGenealogyGraphState;

  const InviteGenealogyGraphState._();
}
