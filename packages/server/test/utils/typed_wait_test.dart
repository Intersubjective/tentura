import 'dart:async';

import 'package:test/test.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/utils/typed_wait.dart';

Future<T> _ok<T>(int ms, T value) =>
    Future<T>.delayed(Duration(milliseconds: ms), () => value);

Future<T> _fail<T>(int ms, Object error, [StackTrace? stackTrace]) =>
    Future<void>.delayed(
      Duration(milliseconds: ms),
    ).then((_) => Future<T>.error(error, stackTrace));

final class _Boom implements Exception {
  const _Boom(this.name);
  final String name;
}

void main() {
  group('typed waitAll', () {
    test('values land in their own positions and types', () async {
      final (n, s, l, m, b, d) = await (
        _ok<int>(30, 1),
        _ok<String>(10, 's'),
        _ok<List<String>>(20, ['x']),
        _ok<Map<String, int>>(0, {'k': 2}),
        _ok<bool>(5, true),
        _ok<double>(15, 1.5),
      ).waitAll;
      expect(n, 1);
      expect(s, 's');
      expect(l, ['x']);
      expect(m, {'k': 2});
      expect(b, isTrue);
      expect(d, 1.5);
    });

    test('a failure surfaces the original exception, not a wrapper', () async {
      const error = UnauthorizedException(description: 'no');
      await expectLater(
        (_ok<int>(0, 1), _fail<String>(5, error), _ok<bool>(0, true)).waitAll,
        throwsA(same(error)),
      );
    });

    test(
      'several failures: the first in time wins, as with Future.wait',
      () async {
        const early = _Boom('early');
        const late = _Boom('late');

        Object? fromFutureWait;
        try {
          await Future.wait<Object?>([
            _fail<int>(30, late),
            _ok<String>(0, 's'),
            _fail<bool>(5, early),
          ]);
        } on Object catch (e) {
          fromFutureWait = e;
        }

        Object? fromWaitAll;
        try {
          await (
            _fail<int>(30, late),
            _ok<String>(0, 's'),
            _fail<bool>(5, early),
          ).waitAll;
        } on Object catch (e) {
          fromWaitAll = e;
        }

        expect(fromFutureWait, same(early));
        expect(fromWaitAll, same(early));
      },
    );

    test('the original stack trace travels with the error', () async {
      final thrownAt = StackTrace.current;
      StackTrace? caught;
      try {
        await (
          _fail<int>(0, const _Boom('x'), thrownAt),
          _ok<String>(0, 's'),
        ).waitAll;
      } on _Boom catch (_, st) {
        caught = st;
      }
      expect(caught, same(thrownAt));
    });

    test('waits for every future even after one fails', () async {
      var slowDone = false;
      final slow = Future<int>.delayed(const Duration(milliseconds: 30), () {
        slowDone = true;
        return 1;
      });
      await expectLater(
        (slow, _fail<int>(0, const _Boom('x')), Future.value(2)).waitAll,
        throwsA(isA<_Boom>()),
      );
      expect(slowDone, isTrue);
    });

    test('arities 2, 4 and 5 type their slots', () async {
      final (a, b) = await (Future.value(1), Future.value('b')).waitAll;
      final (c, d, e, f) = await (
        Future.value(1),
        Future.value('b'),
        Future.value(true),
        Future.value(<int>[3]),
      ).waitAll;
      final (g, h, i, j, k) = await (
        Future.value(1),
        Future.value('b'),
        Future.value(true),
        Future.value(<int>[3]),
        Future.value(4.0),
      ).waitAll;
      expect(
        [a, b, c, d, e, f, g, h, i, j, k],
        [
          1,
          'b',
          1,
          'b',
          true,
          [3],
          1,
          'b',
          true,
          [3],
          4.0,
        ],
      );
    });
  });
}
