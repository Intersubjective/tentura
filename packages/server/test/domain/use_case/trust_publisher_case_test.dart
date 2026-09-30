import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/env.dart';

Env _testEnv() => Env(
  environment: Environment.test,
  publicOrigin: 'https://t.example',
  unsubscribeSigningSecret: 'secret',
);

class _FakePort implements TrustPublishPort {
  bool cutover = false;
  int? token = 7;
  List<PublishRow> batch = const [];

  /// Number of `leaseValid` calls that return true before it flips to false.
  int validCalls = 1 << 30;
  Object? publishError;

  final calls = <String>[];
  final owners = <String>[];
  final published = <String>[];
  final acked = <List<String>>[];
  final ackTokens = <int>[];
  final failed = <List<String>>[];
  final failErrors = <String>[];
  int? readLimit;

  @override
  Future<bool> cutoverPending() async {
    calls.add('cutoverPending');
    return cutover;
  }

  @override
  Future<int?> acquireLease(String owner) async {
    calls.add('acquireLease');
    owners.add(owner);
    return token;
  }

  @override
  Future<bool> leaseValid(int token) async {
    calls.add('leaseValid');
    return validCalls-- > 0;
  }

  @override
  Future<List<PublishRow>> readBatch(int limit) async {
    calls.add('readBatch');
    readLimit = limit;
    return batch;
  }

  @override
  Future<void> publish(PublishRow row) async {
    calls.add('publish');
    if (publishError != null) throw publishError!;
    published.add('${row.subject}>${row.object}');
  }

  @override
  Future<void> sync() async => calls.add('sync');

  @override
  Future<void> ack(int token, List<PublishRow> rows) async {
    calls.add('ack');
    ackTokens.add(token);
    acked.add([for (final r in rows) '${r.subject}>${r.object}']);
  }

  @override
  Future<void> fail(List<PublishRow> rows, String error) async {
    calls.add('fail');
    failed.add([for (final r in rows) '${r.subject}>${r.object}']);
    failErrors.add(error);
  }
}

TrustPublisherCase _case(_FakePort port) => TrustPublisherCase(
  port,
  env: _testEnv(),
  logger: Logger('test'),
);

void main() {
  const a = PublishRow('Ua', 'Ub', 0.5);
  const b = PublishRow('Uc', 'Ud', 0);

  test('pending cutover reads nothing and takes no lease', () async {
    final port = _FakePort()
      ..cutover = true
      ..batch = [a];

    await _case(port).run();

    expect(port.calls, ['cutoverPending']);
  });

  test('no lease means no batch is read', () async {
    final port = _FakePort()
      ..token = null
      ..batch = [a];

    await _case(port).run();

    expect(port.calls, contains('acquireLease'));
    expect(port.calls, isNot(contains('readBatch')));
    expect(port.calls, isNot(contains('publish')));
    expect(port.calls, isNot(contains('ack')));
  });

  test('publishes each row under a valid lease, syncs, then acks', () async {
    final port = _FakePort()..batch = [a, b];

    await _case(port).run();

    expect(port.readLimit, 200);
    expect(port.published, ['Ua>Ub', 'Uc>Ud']);
    expect(port.calls.indexOf('sync'), greaterThan(port.calls.lastIndexOf('publish')));
    expect(port.calls.last, 'ack');
    expect(port.acked, [
      ['Ua>Ub', 'Uc>Ud'],
    ]);
    expect(port.ackTokens, [7]);
    expect(port.failed, isEmpty);
    // One MR barrier per batch, not one per row.
    expect(port.calls.where((c) => c == 'sync'), hasLength(1));
  });

  test('checks the lease before every publish', () async {
    final port = _FakePort()..batch = [a, b];

    await _case(port).run();

    final firstPublish = port.calls.indexOf('publish');
    expect(port.calls[firstPublish - 1], 'leaseValid');
    expect(
      port.calls.where((c) => c == 'leaseValid').length,
      greaterThanOrEqualTo(2),
    );
  });

  test('publish failure records fail and never acks', () async {
    final port = _FakePort()
      ..batch = [a]
      ..publishError = StateError('mr down');

    await _case(port).run();

    expect(port.failed, [
      ['Ua>Ub'],
    ]);
    expect(port.failErrors.single, contains('mr down'));
    expect(port.acked, isEmpty);
  });

  test('lease lost mid-batch stops publishing and does not ack', () async {
    final port = _FakePort()
      ..batch = [a, b]
      ..validCalls = 1;

    await _case(port).run();

    expect(port.published, ['Ua>Ub']);
    expect(port.calls.where((c) => c == 'publish'), hasLength(1));
    expect(port.calls, isNot(contains('sync')));
    expect(port.calls, isNot(contains('ack')));
    expect(port.calls, isNot(contains('fail')));
  });

  test('uses one stable instance id across runs', () async {
    final port = _FakePort();
    final useCase = _case(port);

    await useCase.run();
    await useCase.run();

    expect(port.owners, hasLength(2));
    expect(port.owners.first, isNotEmpty);
    expect(port.owners.first, port.owners.last);
  });

  test('nudge never runs the publisher itself', () async {
    final port = _FakePort()..batch = [a];
    final useCase = _case(port);

    useCase.nudge();
    useCase.nudge();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(port.calls, isEmpty);
  });
}
