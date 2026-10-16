// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/complaint/domain/util/complaint_details.dart';

void main() {
  const message = 'Please provide details';

  test('details shorter than the labelled minimum are rejected', () {
    for (final value in [null, '', '   ', 'ab', ' ab ', '👍👍']) {
      expect(
        validateComplaintDetails(value, message),
        message,
        reason: '$value',
      );
    }
  });

  test('three or more characters pass', () {
    for (final value in ['abc', ' abc ', 'Spam links', '👍👍👍']) {
      expect(validateComplaintDetails(value, message), isNull, reason: value);
    }
  });
}
