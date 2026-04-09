import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

void main() {
  group('InboxItemStatus tombstone', () {
    test('maps smallints 3 and 4', () {
      expect(
        inboxItemStatusFromSmallint(3),
        InboxItemStatus.closedBeforeResponse,
      );
      expect(
        inboxItemStatusFromSmallint(4),
        InboxItemStatus.deletedBeforeResponse,
      );
      expect(InboxItemStatus.closedBeforeResponse.toSmallint, 3);
      expect(InboxItemStatus.deletedBeforeResponse.toSmallint, 4);
    });
  });
}
