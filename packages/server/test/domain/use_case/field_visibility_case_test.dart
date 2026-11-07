import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/field_hidden_item.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/entity/person_field_items_page.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/field_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/field_visibility_case.dart';

const _result = (
  people: <FieldSearchPerson>[(id: 'Up', displayName: 'P', handle: null)],
  requests: <FieldSearchRequestHit>[],
  posts: <FieldSearchPostHit>[],
);

const PersonFieldItemsPage _page = (
  items: <PersonFieldItem>[],
  nextCursor: null,
  counts: (active: 1, closed: 2, hidden: 3),
);

/// Records every call's arguments; answers with fixed values.
final class _FakeRepository implements FieldVisibilityRepositoryPort {
  final calls = <String, Map<String, Object?>>{};

  final hidden = <FieldHiddenItem>[
    (
      targetKind: FieldTargetKind.post,
      targetId: 'Bpost',
      title: 'T',
      authorId: 'Ua',
      hiddenAt: DateTime.utc(2026, 11, 2),
    ),
  ];

  @override
  Future<FieldSearchResult> search({
    required String viewerId,
    required String context,
    required List<String> words,
  }) async {
    calls['search'] = {
      'viewerId': viewerId,
      'context': context,
      'words': words,
    };
    return _result;
  }

  @override
  Future<PersonFieldItemsPage> personItems({
    required String viewerId,
    required String personId,
    required PersonFieldBucket bucket,
    required List<String> words,
    PersonFieldCursor? cursor,
  }) async {
    calls['personItems'] = {
      'viewerId': viewerId,
      'personId': personId,
      'bucket': bucket,
      'words': words,
      'cursor': cursor,
    };
    return _page;
  }

  @override
  Future<void> setHidden({
    required String viewerId,
    required FieldTargetKind targetKind,
    required String targetId,
    required bool hidden,
  }) async {
    calls['setHidden'] = {
      'viewerId': viewerId,
      'targetKind': targetKind,
      'targetId': targetId,
      'hidden': hidden,
    };
  }

  @override
  Future<List<FieldHiddenItem>> hiddenItems({
    required String viewerId,
    DateTime? before,
  }) async {
    calls['hiddenItems'] = {'viewerId': viewerId, 'before': before};
    return hidden;
  }
}

void main() {
  late _FakeRepository repository;
  late FieldVisibilityCase case_;

  setUp(() {
    repository = _FakeRepository();
    case_ = FieldVisibilityCase(repository);
  });

  group('search', () {
    for (final (viewerId, query) in [
      ('', 'garden'),
      ('  ', 'garden'),
      ('Uviewer', ''),
      ('Uviewer', 'a'),
      ('Uviewer', ' @a@ '),
    ]) {
      test('empty result without a repository call for '
          'viewer "$viewerId", query "$query"', () async {
        final result = await case_.search(
          viewerId: viewerId,
          query: query,
          context: 'field',
        );
        expect(result, emptyFieldSearchResult);
        expect(repository.calls, isEmpty);
      });
    }

    test('folds case, ё and @, and splits on any Unicode whitespace', () async {
      final result = await case_.search(
        viewerId: 'Uviewer',
        query: '  @Ёлка\u00a0Сад\tGARDEN\u3000 ',
        context: 'mention',
      );

      expect(result, _result);
      expect(repository.calls['search'], {
        'viewerId': 'Uviewer',
        'context': 'mention',
        'words': ['елка', 'сад', 'garden'],
      });
    });

    test('two runes are enough', () async {
      await case_.search(viewerId: 'Uviewer', query: 'ab', context: 'field');
      expect(repository.calls['search']?['words'], ['ab']);
    });
  });

  group('personItems', () {
    test('rejects a blank person id before reading', () {
      expect(
        () => case_.personItems(
          viewerId: 'Uviewer',
          personId: ' ',
          bucket: PersonFieldBucket.active,
        ),
        throwsA(isA<IdWrongException>()),
      );
      expect(repository.calls, isEmpty);
    });

    test('passes bucket, cursor and folded words through', () async {
      final cursor = (activityAt: DateTime.utc(2026, 11, 3), id: 'Bc');
      final page = await case_.personItems(
        viewerId: 'Uviewer',
        personId: 'Uperson',
        bucket: PersonFieldBucket.closed,
        query: 'Old  Ёж',
        cursor: cursor,
      );

      expect(page, _page);
      expect(repository.calls['personItems'], {
        'viewerId': 'Uviewer',
        'personId': 'Uperson',
        'bucket': PersonFieldBucket.closed,
        'words': ['old', 'еж'],
        'cursor': cursor,
      });
    });

    test('an empty query filters nothing', () async {
      await case_.personItems(
        viewerId: 'Uviewer',
        personId: 'Uperson',
        bucket: PersonFieldBucket.hidden,
      );
      expect(repository.calls['personItems']?['words'], isEmpty);
    });
  });

  group('setHidden', () {
    test('rejects a blank target id before writing', () {
      expect(
        () => case_.setHidden(
          viewerId: 'Uviewer',
          targetKind: FieldTargetKind.request,
          targetId: '',
          hidden: true,
        ),
        throwsA(isA<IdWrongException>()),
      );
      expect(repository.calls, isEmpty);
    });

    test('writes the viewer row as given', () async {
      await case_.setHidden(
        viewerId: 'Uviewer',
        targetKind: FieldTargetKind.post,
        targetId: 'Bpost',
        hidden: false,
      );
      expect(repository.calls['setHidden'], {
        'viewerId': 'Uviewer',
        'targetKind': FieldTargetKind.post,
        'targetId': 'Bpost',
        'hidden': false,
      });
    });
  });

  test('hiddenItems reads the viewer list with its cursor', () async {
    final before = DateTime.utc(2026, 11, 4);
    final items = await case_.hiddenItems(viewerId: 'Uviewer', before: before);
    expect(items, repository.hidden);
    expect(repository.calls['hiddenItems'], {
      'viewerId': 'Uviewer',
      'before': before,
    });
  });
}
