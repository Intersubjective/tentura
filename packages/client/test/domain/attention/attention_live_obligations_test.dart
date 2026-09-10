import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../features/block/support/controllable_block_case.dart'
    show noopBlockCase;
import '../../support/test_realtime_sync.dart';

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

final class _Repository implements AttentionRepositoryPort {
  Set<String> obligationBeaconIds = const {};
  Object? failWith;

  @override
  Future<Set<String>> liveObligationBeacons() async {
    final error = failWith;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return obligationBeaconIds;
  }

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      throw UnimplementedError();

  @override
  Future<int> markAllSeen() async => throw UnimplementedError();

  @override
  Future<int> markSeen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> markUnseen(List<String> ids) async => throw UnimplementedError();

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      throw UnimplementedError();
}

void main() {
  late _Repository repository;
  late AttentionCase attention;

  setUp(() {
    repository = _Repository();
    final realtime = buildTestRealtimeSync();
    attention = AttentionCase(
      repository,
      _Accounts(),
      realtime.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('attention-live-obligations-test'),
      qaLatencyMeasurementEnabled: false,
    );
  });

  tearDown(() => attention.dispose());

  test('returns an empty set when the port reports no obligations', () async {
    repository.obligationBeaconIds = const {};

    expect(await attention.liveObligationBeacons(), isEmpty);
  });

  test('returns beacon ids from the port', () async {
    repository.obligationBeaconIds = {'beacon-a', 'beacon-b'};

    expect(
      await attention.liveObligationBeacons(),
      {'beacon-a', 'beacon-b'},
    );
  });

  test('propagates port failures instead of returning an empty set', () async {
    repository.failWith = StateError('unavailable');

    expect(
      () => attention.liveObligationBeacons(),
      throwsA(isA<StateError>()),
    );
  });
}
