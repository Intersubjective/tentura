import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';

void main() {
  group('My Work layout packing helpers', () {
    late TenturaTokens expanded;

    setUp(() {
      expanded = TenturaTokens.light.applyWindowClass(WindowClass.expanded);
    });

    test('separator width matches live Row chrome', () {
      expect(myWorkMasterDetailSeparatorWidth(expanded), 73);
    });

    test('detailFitsOpsRoom respects comfortable and tight floors', () {
      expect(myWorkDetailFitsOpsRoom(719, tight: false), isFalse);
      expect(myWorkDetailFitsOpsRoom(720, tight: false), isTrue);

      expect(myWorkDetailFitsOpsRoom(559, tight: true), isFalse);
      expect(myWorkDetailFitsOpsRoom(560, tight: true), isTrue);
    });

    test('fitsFour is false at ~840 viewport body budget (~535px)', () {
      expect(myWorkFitsFourColumns(535, expanded), isFalse);
    });

    test('fitsFour needs master + separators + comfortable ops|room pair', () {
      final master = deskMasterPaneWidth(1353, expanded);
      final detail =
          1353 - master - myWorkMasterDetailSeparatorWidth(expanded);
      expect(detail, 720);
      expect(myWorkFitsFourColumns(1353, expanded), isTrue);
    });

    test('collapsed list at ~1024 viewport body (~720px) fits tight ops|room', () {
      expect(myWorkDetailFitsOpsRoom(720, tight: true), isTrue);
    });
  });
}
