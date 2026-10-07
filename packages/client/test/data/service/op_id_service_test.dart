import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/port/op_id_port.dart';

void main() {
  group('OpIdService', () {
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('is an OpIdPort', () {
      expect(OpIdService(), isA<OpIdPort>());
    });

    test('issues UUID v4 operation ids', () {
      final ids = OpIdService();

      for (var i = 0; i < 20; i++) {
        expect(ids.newOpId(), matches(uuidV4));
      }
    });

    test('never repeats an operation id', () {
      final ids = OpIdService();
      final issued = {for (var i = 0; i < 500; i++) ids.newOpId()};

      expect(issued, hasLength(500));
    });
  });
}
