import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';

void main() {
  test('ThreadMessagePreviewKind.factsBrought is 13 and listed in values', () {
    expect(ThreadMessagePreviewKind.factsBrought, 13);
    expect(
      ThreadMessagePreviewKind.values,
      contains(ThreadMessagePreviewKind.factsBrought),
    );
  });
}
