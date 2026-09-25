import 'package:flutter_test/flutter_test.dart';

import 'beacon_view_case_test_support.dart';

/// Records the raw [Invocation] of `markBeaconPeopleSeen` (via
/// `noSuchMethod`) so tests can assert the exact call shape: positional
/// `beaconId` and no `readThroughAt` argument at all.
class _RecordingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  final invocations = <Invocation>[];
  DateTime seenAt = DateTime.utc(2026, 6, 15, 12, 10);
  Object? error;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #markBeaconPeopleSeen) {
      return super.noSuchMethod(invocation);
    }
    invocations.add(invocation);
    final e = error;
    if (e != null) return Future<DateTime>.error(e);
    return Future<DateTime>.value(seenAt);
  }
}

void main() {
  group('BeaconViewCase.markPeopleSeen', () {
    test('delegates once without readThroughAt and returns seenAt', () async {
      final repo = _RecordingCoordinationRepository();
      final case_ = buildTestBeaconViewCase(coordinationRepo: repo);

      final result = await case_.markPeopleSeen('b1');

      expect(result, repo.seenAt);
      expect(repo.invocations, hasLength(1));
      final call = repo.invocations.single;
      expect(call.positionalArguments, ['b1']);
      expect(call.namedArguments, isEmpty);
    });

    test('propagates repository errors', () async {
      final failure = StateError('boom');
      final repo = _RecordingCoordinationRepository()..error = failure;
      final case_ = buildTestBeaconViewCase(coordinationRepo: repo);

      await expectLater(
        case_.markPeopleSeen('b1'),
        throwsA(same(failure)),
      );
    });
  });
}
