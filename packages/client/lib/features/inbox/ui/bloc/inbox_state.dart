import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'inbox_state.freezed.dart';

@freezed
abstract class InboxState extends StateBase with _$InboxState {
  const factory InboxState({
    @Default([]) List<InboxItem> items,
    @Default(InboxSort.recent) InboxSort sort,
    @Default(StateIsSuccess()) StateStatus status,

    /// Used to hide the current user’s own beacons from the Watching tab.
    @Default('') String currentUserId,
  }) = _InboxState;

  const InboxState._();

  static const _tombstoneWindow = Duration(hours: 24);

  /// Passive tombstones to show under "Resolved beacons" (non-dismissed, last 24h).
  List<InboxItem> get tombstonesLast24h {
    final now = DateTime.now();
    final list = items.where((e) {
      if (!e.isTombstoneVisible) return false;
      final t = e.beforeResponseTerminalAt;
      if (t == null) return false;
      return now.difference(t) <= _tombstoneWindow;
    }).toList()
      ..sort(
        (a, b) =>
            (b.beforeResponseTerminalAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
              a.beforeResponseTerminalAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );
    return list;
  }

  List<InboxItem> get needsMe => _sorted(
        items.where((e) => e.status == InboxItemStatus.needsMe).toList(),
      );

  List<InboxItem> get watching => _sorted(
        items.where((e) {
          if (e.status != InboxItemStatus.watching) return false;
          final authorId = e.beacon?.author.id;
          if (authorId == null || authorId.isEmpty) return true;
          if (currentUserId.isEmpty) return true;
          return authorId != currentUserId;
        }).toList(),
      );

  List<InboxItem> get rejected => _sorted(
        items.where((e) => e.status == InboxItemStatus.rejected).toList(),
      );

  List<InboxItem> _sorted(List<InboxItem> list) {
    switch (sort) {
      case InboxSort.recent:
        list.sort((a, b) => b.latestForwardAt.compareTo(a.latestForwardAt));
      case InboxSort.meritRank:
        list.sort(
          (a, b) => (b.beacon?.score ?? 0).compareTo(a.beacon?.score ?? 0),
        );
      case InboxSort.deadline:
        list.sort((a, b) {
          final ae = a.beacon?.endAt;
          final be = b.beacon?.endAt;
          if (ae == null && be == null) return 0;
          if (ae == null) return 1;
          if (be == null) return -1;
          return ae.compareTo(be);
        });
    }
    return list;
  }
}
