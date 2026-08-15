import 'package:test/test.dart';

import 'package:tentura_server/data/repository/coordination_item_repository.dart';

void main() {
  group('CoordinationItemRepository.roomBodyForCreatedItem', () {
    test('uses trimmed title', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: 'Blocked on API',
        ),
        'Blocked on API',
      );
    });

    test('ignores body', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: 'Ask',
          body: 'Need the file by Friday',
        ),
        'Ask',
      );
    });

    test('returns empty when title empty', () {
      expect(
        CoordinationItemRepository.roomBodyForCreatedItem(
          title: '  ',
          body: 'Details only',
        ),
        '',
      );
    });
  });

  group('CoordinationItemRepository.roomBodyForStandaloneCreatedItem', () {
    test('root plan standalone uses empty body', () {
      expect(
        CoordinationItemRepository.roomBodyForStandaloneCreatedItem(
          kind: 1,
          title: 'Ship by Friday',
        ),
        '',
      );
    });

    test('plan step standalone keeps title body', () {
      expect(
        CoordinationItemRepository.roomBodyForStandaloneCreatedItem(
          kind: 1,
          title: 'Step one',
          linkedParentItemId: 'Iplan0001',
        ),
        'Step one',
      );
    });

    test('ask standalone keeps title body', () {
      expect(
        CoordinationItemRepository.roomBodyForStandaloneCreatedItem(
          kind: 2,
          title: 'Need review',
        ),
        'Need review',
      );
    });
  });
}
