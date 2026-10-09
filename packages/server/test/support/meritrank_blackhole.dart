import 'dart:io';

import 'disposable_pg_target.dart' show isPgTestsRequired, pgTestsRequiredEnvVar;

/// Name of the container the Postgres under test reaches MeritRank through
/// (`MERITRANK_SERVICE_URL=tcp://meritrank:8080` in compose); override with
/// `TENTURA_MERITRANK_CONTAINER`.
const meritRankContainerEnvVar = 'TENTURA_MERITRANK_CONTAINER';

/// Makes the MeritRank service stop answering without closing its socket: the
/// kernel keeps accepting connections and swallowing requests, so the pgmer2
/// connector inside Postgres blocks in its receive wait exactly as it does
/// against a hung or partitioned peer (`docker pause`).
///
/// It acts on the one MeritRank container every pg test shares, so use it only
/// from `mr`-tagged suites (they are serialized) and always [release] in a
/// `finally`/`addTearDown`.
final class MeritRankBlackhole {
  MeritRankBlackhole._(this.container);

  final String container;

  /// A controllable blackhole, or null with the [reason] it is not available
  /// (no docker CLI, or the MeritRank container is not running).
  ///
  /// With `TENTURA_PG_TESTS_REQUIRED=1` an unavailable blackhole is a
  /// [StateError] instead, so a required run cannot silently skip the
  /// scenarios that need it (the same contract as `pgSkipReason`).
  static Future<(MeritRankBlackhole?, String?)> probe({
    Map<String, String>? environment,
  }) async {
    final (blackhole, reason) = await _probe(environment);
    if (blackhole == null && isPgTestsRequired(environment)) {
      throw StateError(
        'MeritRank blackhole required ($pgTestsRequiredEnvVar=1) but '
        'unavailable: $reason',
      );
    }
    return (blackhole, reason);
  }

  static Future<(MeritRankBlackhole?, String?)> _probe(
    Map<String, String>? environment,
  ) async {
    final container =
        (environment ?? Platform.environment)[meritRankContainerEnvVar] ??
        'meritrank';
    try {
      final result = await Process.run('docker', [
        'inspect',
        '--format',
        '{{.State.Running}} {{.State.Paused}}',
        container,
      ]);
      if (result.exitCode != 0 ||
          (result.stdout as String).trim() != 'true false') {
        return (
          null,
          'MeritRank container "$container" is not running and unpaused '
              '(docker inspect: ${(result.stdout as String).trim()} '
              '${(result.stderr as String).trim()})',
        );
      }
    } on Object catch (error) {
      return (null, 'docker is not available to blackhole MeritRank: $error');
    }
    return (MeritRankBlackhole._(container), null);
  }

  Future<void> engage() => _docker('pause');

  /// Idempotent: releasing a service that is not paused is a no-op, so a
  /// `finally` and an `addTearDown` can both call it.
  Future<void> release() => _docker('unpause', tolerate: 'is not paused');

  Future<void> _docker(String verb, {String? tolerate}) async {
    final result = await Process.run('docker', [verb, container]);
    if (result.exitCode != 0 &&
        !(tolerate != null && '${result.stderr}'.contains(tolerate))) {
      throw StateError('docker $verb $container failed: ${result.stderr}');
    }
  }
}
