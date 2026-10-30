@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('W8: tentura_responsive_scope has no master-detail layout helpers', () {
    final source = File(
      'lib/design_system/tentura_responsive_scope.dart',
    ).readAsStringSync();
    for (final symbol in [
      'deskMasterPaneWidth',
      'deskFitsMasterDetail',
      'myWorkMasterDetailSeparatorWidth',
      'deskDetailBudget',
      'kDeskDetailMinWidth',
    ]) {
      expect(source.contains(symbol), isFalse, reason: symbol);
    }
  });
}
