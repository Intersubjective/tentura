import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';

void main() {
  group('Desk layout packing helpers', () {
    late TenturaTokens expanded;

    setUp(() {
      expanded = TenturaTokens.light.applyWindowClass(WindowClass.expanded);
    });

    test('separator width matches live Row chrome', () {
      expect(deskMasterDetailSeparatorWidth(expanded), 49);
      expect(myWorkMasterDetailSeparatorWidth(expanded), 49);
    });

    test('deskFitsMasterDetail respects 360px detail floor', () {
      expect(deskFitsMasterDetail(535, expanded), isFalse);
      expect(deskFitsMasterDetail(719, expanded), isFalse);
      expect(deskFitsMasterDetail(969, expanded), isTrue);
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
      final master = deskMasterPaneWidth(1329, expanded);
      final detail = deskDetailBudget(1329, expanded);
      expect(master, 560);
      expect(detail, 720);
      expect(myWorkFitsFourColumns(1329, expanded), isTrue);
    });

    test('collapsed list at ~1024 viewport body (~720px) fits tight ops|room', () {
      expect(myWorkDetailFitsOpsRoom(720, tight: true), isTrue);
    });
  });
}
