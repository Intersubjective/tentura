import 'package:tentura/ui/bloc/state_base.dart';

part 'thread_host_state.freezed.dart';

@freezed
abstract class ThreadHostState extends StateBase with _$ThreadHostState {
  const factory ThreadHostState({
    String? openThreadId,
    @Default(false) bool switching,
    @Default(0) int selectionGeneration,
  }) = _ThreadHostState;

  const ThreadHostState._();
}
