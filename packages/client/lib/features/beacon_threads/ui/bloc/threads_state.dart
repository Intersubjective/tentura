import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'threads_state.freezed.dart';

@freezed
abstract class ThreadsState extends StateBase with _$ThreadsState {
  const factory ThreadsState({
    @Default([]) List<RequestThread> threads,
    @Default({}) Map<String, int> resolvedUnreadByThreadId,
    @Default('') String myUserId,
    @Default(StateIsSuccess()) StateStatus status,
    Object? loadError,
  }) = _ThreadsState;

  const ThreadsState._();

  bool get hasError => loadError != null;

  RequestThread? get general {
    for (final thread in threads) {
      if (thread.kind == RequestThreadKind.general) {
        return thread;
      }
    }
    return null;
  }

  RequestThread? get firstAccessible => general ?? threads.firstOrNull;

  int resolvedUnreadFor(RequestThread thread) =>
      resolvedUnreadByThreadId[thread.threadId] ?? 0;

  int get threadsTabUnreadCount {
    final g = general;
    if (g == null) return 0;
    return resolvedUnreadFor(g);
  }
}
