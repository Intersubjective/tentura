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
  });
}
