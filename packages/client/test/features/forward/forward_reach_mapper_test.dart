import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/data/mapper/forward_reach_mapper.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';

void main() {
  group('mapForwardReachFromJson', () {
    test('null wire maps to null', () {
      expect(mapForwardReachFromJson(null), isNull);
    });

    test('via_connection with two vouchers', () {
      final reach = mapForwardReachFromJson({
        'kind': 'via_connection',
        'via_count': 2,
        'via': [
          {'id': 'U-a', 'displayName': 'Alice'},
          {'id': 'U-b', 'displayName': 'Bob'},
        ],
      });
      expect(reach, isNotNull);
      expect(reach!.kind, ForwardReachKind.viaConnection);
      expect(reach.viaCount, 2);
      expect(reach.via.map((p) => p.displayName), ['Alice', 'Bob']);
    });

    test('via_connection with one preview and higher via_count', () {
      final reach = mapForwardReachFromJson({
        'kind': 'via_connection',
        'via_count': 5,
        'via': [
          {'id': 'U-a', 'displayName': 'Alice'},
        ],
      });
      expect(reach!.viaCount, 5);
      expect(reach.via, hasLength(1));
    });

    test('shared_request carries title', () {
      final reach = mapForwardReachFromJson({
        'kind': 'shared_request',
        'via_count': 0,
        'via': <Object>[],
        'shared_request_id': 'B1',
        'shared_request_title': 'Moving boxes',
      });
      expect(reach!.kind, ForwardReachKind.sharedRequest);
      expect(reach.sharedRequest?.title, 'Moving boxes');
    });

    test('wider kind', () {
      final reach = mapForwardReachFromJson({
        'kind': 'wider',
        'via_count': 0,
        'via': <Object>[],
      });
      expect(reach!.kind, ForwardReachKind.wider);
    });
  });
}
