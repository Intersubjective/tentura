import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/field_search_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/field_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/saved_fact_repository_port.dart';
import 'package:tentura_server/domain/use_case/field_visibility_case.dart';
import 'package:tentura_server/domain/use_case/saved_fact_case.dart';
import 'package:tentura_server/env.dart';

final class _FakeFacts extends Fake implements BeaconFactCardRepositoryPort {}

typedef _SearchCall = ({
  String userId,
  List<String> words,
  int limit,
  String? excludeBeaconId,
});

final class _FakeSaved implements SavedFactRepositoryPort {
  final calls = <_SearchCall>[];

  final rows = <Map<String, Object?>>[
    {
      'factCardId': 'F1',
      'beaconId': 'B2',
      'beaconKind': 0,
      'factText': 'elka',
      'attachmentsJson': '[]',
      'saved': false,
    },
  ];

  @override
  Future<List<Map<String, Object?>>> search({
    required String userId,
    required List<String> words,
    required int limit,
    String? excludeBeaconId,
  }) async {
    calls.add((
      userId: userId,
      words: words,
      limit: limit,
      excludeBeaconId: excludeBeaconId,
    ));
    return rows;
  }

  @override
  Future<bool> save({
    required String userId,
    required String factCardId,
    required int cap,
  }) async => true;

  @override
  Future<void> unsave({
    required String userId,
    required String factCardId,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> list({required String userId}) async =>
      const [];
}

final class _FakeField extends Fake implements FieldVisibilityRepositoryPort {
  List<String>? words;

  @override
  Future<FieldSearchResult> search({
    required String viewerId,
    required String context,
    required List<String> words,
  }) async {
    this.words = words;
    return emptyFieldSearchResult;
  }
}

void main() {
  late _FakeSaved saved;

  SavedFactCase build({int? max, Duration? window}) {
    saved = _FakeSaved();
    return SavedFactCase(
      _FakeFacts(),
      saved,
      env: Env(
        environment: Environment.test,
        factSearchRateMax: max,
        factEditRateWindow: window,
      ),
      logger: Logger('SavedFactSearchCaseTest'),
    );
  }

  Future<List<Map<String, Object?>>> search(
    SavedFactCase c,
    String q, {
    String user = 'U1',
    String? exclude,
  }) => c.search(userId: user, query: q, excludeBeaconId: exclude);

  group('SavedFactCase.search', () {
    test('folds the query and asks the repository once with the limit, '
        'returning its rows unchanged', () async {
      final c = build();
      final result = await search(c, ' Ёлка Дом ', exclude: 'B1');
      expect(saved.calls, hasLength(1));
      final call = saved.calls.single;
      expect(call.userId, 'U1');
      expect(call.words, ['елка', 'дом']);
      expect(call.excludeBeaconId, 'B1');
      expect(call.limit, kMaxFactSearchResults);
      expect(result, saved.rows);
    });

    test('passes a null exclude when none is given', () async {
      final c = build();
      await search(c, 'ab');
      expect(saved.calls.single.excludeBeaconId, isNull);
    });

    test('splits on Unicode whitespace and drops empty words', () async {
      final c = build();
      await search(c, '  Ёлка \t ДОМ  ');
      expect(saved.calls.single.words, ['елка', 'дом']);
    });

    test('uses the same word list as the Field search for one query',
        () async {
      final field = _FakeField();
      await FieldVisibilityCase(field).search(
        viewerId: 'U1',
        query: '  Ёлка ДОМ  ',
        context: 'c',
      );
      final c = build();
      await search(c, '  Ёлка ДОМ  ');
      expect(saved.calls.single.words, field.words);
      expect(field.words, ['елка', 'дом']);
    });

    test('short queries answer [] without a repository call and without '
        'charging the limit', () async {
      final c = build(max: 2);
      for (final q in [' ё ', 'a', '@a', '']) {
        expect(await search(c, q), isEmpty, reason: q);
      }
      expect(saved.calls, isEmpty);
      await search(c, 'ab');
      await search(c, 'cd');
      expect(saved.calls, hasLength(2));
    });

    test('the search after the maximum inside the window is refused before '
        'the repository', () async {
      final c = build(max: 3);
      for (var i = 0; i < 3; i++) {
        await search(c, 'ab');
      }
      await expectLater(
        search(c, 'ab'),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
      expect(saved.calls, hasLength(3));
    });

    test('the limit is per user', () async {
      final c = build(max: 2);
      await search(c, 'ab');
      await search(c, 'ab');
      await expectLater(
        search(c, 'ab'),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
      await search(c, 'ab', user: 'U2');
      expect(saved.calls.last.userId, 'U2');
    });

    test('the window slides: searches that aged out stop counting', () async {
      final c = build(
        max: 2,
        window: const Duration(milliseconds: 200),
      );
      await search(c, 'ab');
      await search(c, 'ab');
      await expectLater(
        search(c, 'ab'),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await search(c, 'ab');
      expect(saved.calls, hasLength(3));
    });
  });
}
