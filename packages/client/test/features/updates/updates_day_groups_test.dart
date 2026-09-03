import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_day_groups.dart';

AttentionReceipt _receipt({
  required String id,
  required DateTime createdAt,
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'needsMe',
  priority: 'normal',
  title: id,
  body: id,
  actionUrl: '/#/',
  createdAt: createdAt,
  collapsedCount: 1,
  presentationPayloadJson: '{}',
);

void main() {
  test('groups by local day and keeps feed order', () {
    final late = DateTime(2026, 8, 5, 1);
    final earlySame = DateTime(2026, 8, 5, 23);
    final previous = DateTime(2026, 8, 4, 22);
    final items = [
      _receipt(id: 'a', createdAt: late),
      _receipt(id: 'b', createdAt: earlySame),
      _receipt(id: 'c', createdAt: previous),
    ];

    final groups = groupUpdatesByLocalDay(items);
    expect(groups, hasLength(2));
    expect(groups[0].$1, DateTime(2026, 8, 5));
    expect(groups[0].$2.map((r) => r.id), ['a', 'b']);
    expect(groups[1].$1, DateTime(2026, 8, 4));
    expect(groups[1].$2.single.id, 'c');
  });

  test('pagination concat merges the same local day', () {
    final page1 = [_receipt(id: 'a', createdAt: DateTime(2026, 8, 5, 18))];
    final page2 = [
      _receipt(id: 'b', createdAt: DateTime(2026, 8, 5, 9)),
      _receipt(id: 'c', createdAt: DateTime(2026, 8, 4, 20)),
    ];

    final groups = groupUpdatesByLocalDay([...page1, ...page2]);
    expect(groups, hasLength(2));
    expect(groups[0].$2.map((r) => r.id), ['a', 'b']);
    expect(groups[1].$2.single.id, 'c');
  });

  test('flatten inserts headers, row hairlines, then load-more', () {
    final items = [
      _receipt(id: 'a', createdAt: DateTime(2026, 8, 5, 12)),
      _receipt(id: 'b', createdAt: DateTime(2026, 8, 5, 11)),
      _receipt(id: 'c', createdAt: DateTime(2026, 8, 4, 9)),
    ];
    final cells = flattenUpdatesFeed(items: items, hasNextPage: true);
    expect(cells.map((c) => c.kind), [
      UpdatesFeedCellKind.header,
      UpdatesFeedCellKind.row,
      UpdatesFeedCellKind.row,
      UpdatesFeedCellKind.header,
      UpdatesFeedCellKind.row,
      UpdatesFeedCellKind.loadMore,
    ]);
    expect(cells[1].showDividerBelow, isTrue);
    expect(cells[2].showDividerBelow, isFalse);
    expect(cells[4].showDividerBelow, isFalse);
  });
}
