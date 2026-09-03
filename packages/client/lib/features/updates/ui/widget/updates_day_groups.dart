import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Groups [items] by local calendar day, preserving feed order.
List<(DateTime day, List<AttentionReceipt> items)> groupUpdatesByLocalDay(
  List<AttentionReceipt> items,
) {
  if (items.isEmpty) return const [];
  final groups = <DateTime, List<AttentionReceipt>>{};
  final order = <DateTime>[];
  for (final item in items) {
    final local = item.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final existing = groups[day];
    if (existing == null) {
      groups[day] = [item];
      order.add(day);
    } else {
      existing.add(item);
    }
  }
  return [for (final day in order) (day, List<AttentionReceipt>.from(groups[day]!))];
}

enum UpdatesFeedCellKind { header, row, loadMore }

class UpdatesFeedCell {
  const UpdatesFeedCell.header(this.day)
    : kind = UpdatesFeedCellKind.header,
      receipt = null,
      showDividerBelow = false;

  const UpdatesFeedCell.row(
    this.receipt, {
    required this.showDividerBelow,
  }) : kind = UpdatesFeedCellKind.row,
       day = null;

  const UpdatesFeedCell.loadMore()
    : kind = UpdatesFeedCellKind.loadMore,
      day = null,
      receipt = null,
      showDividerBelow = false;

  final UpdatesFeedCellKind kind;
  final DateTime? day;
  final AttentionReceipt? receipt;
  final bool showDividerBelow;
}

List<UpdatesFeedCell> flattenUpdatesFeed({
  required List<AttentionReceipt> items,
  required bool hasNextPage,
}) {
  final cells = <UpdatesFeedCell>[];
  for (final (day, receipts) in groupUpdatesByLocalDay(items)) {
    cells.add(UpdatesFeedCell.header(day));
    for (var i = 0; i < receipts.length; i++) {
      cells.add(
        UpdatesFeedCell.row(
          receipts[i],
          showDividerBelow: i < receipts.length - 1,
        ),
      );
    }
  }
  if (hasNextPage) cells.add(const UpdatesFeedCell.loadMore());
  return cells;
}

String updatesDayHeaderLabel({
  required DateTime day,
  required DateTime now,
  required L10n l10n,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return l10n.beaconRoomDateToday;
  if (d == today.subtract(const Duration(days: 1))) {
    return l10n.beaconRoomDateYesterday;
  }
  return dateFormatYMD(d);
}
