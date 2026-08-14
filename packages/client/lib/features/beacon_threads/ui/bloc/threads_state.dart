import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'threads_state.freezed.dart';

@freezed
abstract class ThreadsState extends StateBase with _$ThreadsState {
  const factory ThreadsState({
    @Default([]) List<RequestThread> threads,
    @Default({}) Map<String, int> resolvedUnreadByThreadId,
    @Default(false) bool activeForMeOnly,
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

  List<RequestThread> get active {
    final publishedActive = threads.where(
      (t) => t.item != null && t.item!.published && t.item!.isActive,
    );
    if (!activeForMeOnly) {
      return publishedActive.toList();
    }
    final items = publishedActive.map((t) => t.item!).toList();
    final filteredItems = filterActiveItemsForUser(
      openItems: items,
      userId: myUserId,
      forMeOnly: true,
    );
    final allowedIds = filteredItems.map((i) => i.id).toSet();
    return publishedActive
        .where((t) => allowedIds.contains(t.item!.id))
        .toList();
  }

  List<RequestThread> get closed => threads
      .where(
        (t) => t.item != null && t.item!.published && !t.item!.isActive,
      )
      .toList();

  List<RequestThread> get drafts =>
      threads.where((t) => t.item?.published == false).toList();

  RequestThread? get firstAccessible => general ?? threads.firstOrNull;

  int resolvedUnreadFor(RequestThread thread) =>
      resolvedUnreadByThreadId[thread.threadId] ?? 0;

  int get threadsTabUnreadCount {
    var total = 0;
    final g = general;
    if (g != null) {
      total += resolvedUnreadFor(g);
    }
    for (final thread in active) {
      total += resolvedUnreadFor(thread);
    }
    return total;
  }
}
