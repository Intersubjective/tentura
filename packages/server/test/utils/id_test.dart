import 'dart:developer';
import 'package:test/test.dart';

import 'package:tentura_server/utils/id.dart';

void main() {
  test('Test of id generator', () {
    final userId = generateId('U');
    log(userId);

    expect(userId, hasLength(13));
    expect(userId, startsWith('U'));
    expect(userId.substring(1), matches(r'^[0-9a-f]{12}$'));
  });
}
