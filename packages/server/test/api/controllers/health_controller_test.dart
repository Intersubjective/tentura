// `/health` must carry the MeritRank walks-cache and snapshot state, so an
// operator sees a cache that has fallen below the active readers (every read
// then recalculates peer frames) without profiling.
//
// Contract pinned here:
//  * `MeritrankStatusPort.status()` returns a `MeritrankStatus` with the walks
//    cache size, the number of active readers, and snapshot bytes used / budget.
//  * `HealthController(env, statusPort).handler` answers 200 with JSON
//    `{"status": "ok", "meritrank": {...}}`. The `meritrank` object has
//    `available`, `walksCacheSize`, `activeReaders`, `walksCacheOverCapacity`
//    (readers > cache size), `snapshotBytes`, `snapshotBudgetBytes` and
//    `snapshotPressure` (snapshot bytes at or over the budget).
//  * An unreachable MeritRank never turns `/health` into an error: the route
//    still answers 200 with `"available": false`.
//  * `RootRouter` serves `/health` through that controller.

@Tags(['repo-files'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/health_controller.dart';
import 'package:tentura_server/domain/entity/meritrank_status.dart';
import 'package:tentura_server/domain/port/meritrank_status_port.dart';
import 'package:tentura_server/env.dart';

class _FakeMeritrankStatus implements MeritrankStatusPort {
  _FakeMeritrankStatus(this._status, {this.fails = false, this.hangs = false});

  final MeritrankStatus _status;

  final bool fails;

  final bool hangs;

  @override
  Future<MeritrankStatus> status() async {
    if (hangs) {
      return Completer<MeritrankStatus>().future;
    }
    if (fails) {
      throw StateError('MeritRank unreachable');
    }
    return _status;
  }
}

const _mib = 1024 * 1024;

MeritrankStatus _status({
  int? walksCacheSize,
  int? activeReaders,
  int? snapshotBytes,
  int? snapshotBudgetBytes,
}) => MeritrankStatus(
  walksCacheSize: walksCacheSize ?? 300,
  activeReaders: activeReaders ?? 202,
  snapshotBytes: snapshotBytes ?? 100 * _mib,
  snapshotBudgetBytes: snapshotBudgetBytes ?? 256 * _mib,
);

Future<Map<String, dynamic>> _health(
  MeritrankStatus status, {
  bool fails = false,
  bool hangs = false,
}) async {
  final controller = HealthController(
    Env(),
    _FakeMeritrankStatus(status, fails: fails, hangs: hangs),
  );
  final response = await controller.handler(
    Request('GET', Uri.parse('http://localhost/health')),
  );
  expect(response.statusCode, 200);
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/compose.prod.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = parent;
  }
  return dir;
}

void main() {
  group('health response, MeritRank walks cache', () {
    test('reports the cache size and active readers it was given', () async {
      final body = await _health(
        _status(walksCacheSize: 300, activeReaders: 202),
      );
      expect(body['status'], 'ok');
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['available'], isTrue);
      expect(mr['walksCacheSize'], 300);
      expect(mr['activeReaders'], 202);
    });

    test('flags over-capacity when active readers exceed the cache', () async {
      final body = await _health(
        _status(walksCacheSize: 200, activeReaders: 202),
      );
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['walksCacheOverCapacity'], isTrue);
    });

    test(
      'does not flag over-capacity when the cache covers the readers',
      () async {
        final roomy = await _health(
          _status(walksCacheSize: 300, activeReaders: 202),
        );
        expect(
          (roomy['meritrank']
              as Map<String, dynamic>)['walksCacheOverCapacity'],
          isFalse,
        );
        final exact = await _health(
          _status(walksCacheSize: 202, activeReaders: 202),
        );
        expect(
          (exact['meritrank']
              as Map<String, dynamic>)['walksCacheOverCapacity'],
          isFalse,
        );
      },
    );
  });

  group('health response, MeritRank snapshots', () {
    test('flags snapshot pressure when snapshots fill the budget', () async {
      final body = await _health(
        _status(snapshotBytes: 256 * _mib, snapshotBudgetBytes: 256 * _mib),
      );
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['snapshotPressure'], isTrue);
      expect(mr['snapshotBytes'], 256 * _mib);
      expect(mr['snapshotBudgetBytes'], 256 * _mib);
    });

    test('does not flag snapshot pressure while the budget has room', () async {
      final body = await _health(
        _status(snapshotBytes: 64 * _mib, snapshotBudgetBytes: 256 * _mib),
      );
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['snapshotPressure'], isFalse);
    });

    test('over-capacity and snapshot pressure are independent', () async {
      final body = await _health(
        _status(
          walksCacheSize: 300,
          activeReaders: 202,
          snapshotBytes: 256 * _mib,
          snapshotBudgetBytes: 256 * _mib,
        ),
      );
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['walksCacheOverCapacity'], isFalse);
      expect(mr['snapshotPressure'], isTrue);
    });
  });

  group('health response when MeritRank cannot be read', () {
    test('still answers 200 and reports MeritRank as unavailable', () async {
      final body = await _health(_status(), fails: true);
      expect(body['status'], 'ok');
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr['available'], isFalse);
    });

    test('a hanging status read does not hold the liveness probe', () async {
      final watch = Stopwatch()..start();
      final body = await _health(_status(), hangs: true);
      watch.stop();
      expect(body['status'], 'ok');
      expect((body['meritrank'] as Map<String, dynamic>)['available'], isFalse);
      expect(
        watch.elapsed,
        lessThan(kHealthStatusTimeout + const Duration(seconds: 1)),
      );
    });

    test('unknown snapshot usage reports unknown pressure', () async {
      final body = await _health(
        const MeritrankStatus(
          walksCacheSize: 300,
          activeReaders: 202,
          snapshotBudgetBytes: 256 * _mib,
        ),
      );
      final mr = body['meritrank'] as Map<String, dynamic>;
      expect(mr.containsKey('snapshotPressure'), isTrue);
      expect(mr['snapshotPressure'], isNull);
      expect(mr['snapshotBytes'], isNull);
    });
  });

  group('root router health route', () {
    test('serves /health through the health controller', () {
      final router = File(
        '${_repoRoot().path}/packages/server/lib/api/root_router.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r"\.get\(\s*'/health'\s*,\s*_healthController\.handler\b",
        ).hasMatch(router),
        isTrue,
        reason: '/health is not served by HealthController.handler',
      );
    });
  });
}
