import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/policy/fact_search_rate_limiter.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/saved_fact_repository_port.dart';
import 'package:tentura_server/domain/use_case/saved_fact_case.dart';
import 'package:tentura_server/env.dart';

final class _FakeFacts extends Fake implements BeaconFactCardRepositoryPort {}

final class _FakeSaved extends Fake implements SavedFactRepositoryPort {
  final searched = <List<String>>[];

  @override
  Future<List<Map<String, Object?>>> search({
    required String userId,
    required List<String> words,
    required int limit,
    String? excludeBeaconId,
  }) async {
    searched.add(words);
    return const [];
  }
}

/// How many users the limiter still tracks, read through the test-visible
/// `trackedUsers` count (the map itself is private).
int _tracked(FactSearchRateLimiter limiter) {
  try {
    return (limiter as dynamic).trackedUsers as int;
    // A limiter without the count is the missing behaviour, reported as such.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError catch (e) {
    fail('FactSearchRateLimiter exposes no trackedUsers count: $e');
  }
}

void main() {
  late _FakeSaved saved;

  SavedFactCase build({int? max}) {
    saved = _FakeSaved();
    return SavedFactCase(
      _FakeFacts(),
      saved,
      env: Env(environment: Environment.test, factSearchRateMax: max),
      logger: Logger('SavedFactSearchQueryCapTest'),
    );
  }

  group('SavedFactCase.search caps the query', () {
    test('a 5000-character single word reaches the repository as one '
        '100-character word', () async {
      final c = build();
      await c.search(userId: 'U1', query: 'a' * 5000);
      expect(saved.searched, [
        ['a' * 100],
      ]);
    });

    test(
      'a ten-word query reaches the repository as its first six words',
      () async {
        final c = build();
        await c.search(userId: 'U1', query: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10');
        expect(saved.searched, [
          ['w1', 'w2', 'w3', 'w4', 'w5', 'w6'],
        ]);
      },
    );

    test(
      'an over-long query charges the rate limit once, like any query',
      () async {
        final c = build(max: 2);
        await c.search(userId: 'U1', query: 'a' * 5000);
        await c.search(userId: 'U1', query: 'a' * 5000);
        await expectLater(
          c.search(userId: 'U1', query: 'a' * 5000),
          throwsA(isA<BeaconFactCardRateLimitedException>()),
        );
        expect(saved.searched, hasLength(2));
      },
    );
  });

  group('FactSearchRateLimiter prunes stale users', () {
    test('after the window, one acquire drops every other idle user from '
        'the tracked map', () async {
      final limiter = FactSearchRateLimiter(
        max: 2,
        window: const Duration(milliseconds: 200),
      );
      for (var i = 0; i < 50; i++) {
        expect(limiter.tryAcquire('U$i'), isTrue);
      }
      expect(_tracked(limiter), 50);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(limiter.tryAcquire('Z'), isTrue);
      expect(_tracked(limiter), 1);
    });

    test('a prune triggered by another user does not reset a user still '
        'inside the window', () async {
      final limiter = FactSearchRateLimiter(
        max: 2,
        window: const Duration(milliseconds: 300),
      );
      expect(limiter.tryAcquire('U2'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(limiter.tryAcquire('U1'), isTrue);
      expect(limiter.tryAcquire('U1'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      // U2's hit is stale now, U1's are not.
      expect(limiter.tryAcquire('U2'), isTrue);
      expect(limiter.tryAcquire('U1'), isFalse);
    });
  });

  group('SavedFactCase.search keeps the limit across pruning', () {
    test('a search by another user after the window does not free a user '
        'still inside it', () async {
      saved = _FakeSaved();
      final c = SavedFactCase(
        _FakeFacts(),
        saved,
        env: Env(
          environment: Environment.test,
          factSearchRateMax: 2,
          factEditRateWindow: const Duration(milliseconds: 300),
        ),
        logger: Logger('SavedFactSearchQueryCapTest'),
      );
      await c.search(userId: 'U2', query: 'ab');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await c.search(userId: 'U1', query: 'ab');
      await c.search(userId: 'U1', query: 'ab');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await c.search(userId: 'U2', query: 'ab');
      await expectLater(
        c.search(userId: 'U1', query: 'ab'),
        throwsA(isA<BeaconFactCardRateLimitedException>()),
      );
    });
  });
}
