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

    test('full-width My Work detail at ~1024 viewport fits tight ops|room', () {
      expect(myWorkDetailFitsOpsRoom(720, tight: true), isTrue);
    });
  });
}
