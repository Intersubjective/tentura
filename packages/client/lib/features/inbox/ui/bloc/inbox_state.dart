import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import '../message/inbox_messages.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'inbox_state.freezed.dart';

@freezed
abstract class InboxState extends StateBase with _$InboxState {
  const factory InboxState({
    @Default([]) List<InboxItem> items,
    @Default(StateIsSuccess()) StateStatus status,

    /// True only after a successful Inbox projection fetch.
    @Default(false) bool projectionLoaded,

    /// True when the initial Inbox fetch failed before any successful load.
    @Default(false) bool projectionFailed,

    /// Used to hide the current user’s own beacons from the Watching tab.
    @Default('') String currentUserId,

    InboxBeaconMovedMessage? pendingMovedNudge,
  }) = _InboxState;

  const InboxState._();

  List<InboxItem> get needsMe => _sortedByRecent(
    items.where((e) => e.status == InboxItemStatus.needsMe).toList(),
  );

  List<InboxItem> get watching => _sortedByRecent(
    items.where((e) {
      if (e.status != InboxItemStatus.watching) return false;
      final authorId = e.beacon?.author.id;
      if (authorId == null || authorId.isEmpty) return true;
      if (currentUserId.isEmpty) return true;
      return authorId != currentUserId;
    }).toList(),
  );

  List<InboxItem> get rejected => _sortedByRecent(
    items.where((e) => e.status == InboxItemStatus.rejected).toList(),
  );

  static List<InboxItem> _sortedByRecent(List<InboxItem> list) {
    list.sort((a, b) => b.latestForwardAt.compareTo(a.latestForwardAt));
    return list;
  }
}
