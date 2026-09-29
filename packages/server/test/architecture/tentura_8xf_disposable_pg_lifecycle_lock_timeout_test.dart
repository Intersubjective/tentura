// tentura-8xf acceptance: disposable-pg lifecycle advisory-lock wait must not
// inherit package:postgres default queryTimeout (5 minutes).

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

/// Minimum lock-wait budget under parallel `@Tags(['pg'])` shard contention.
/// Matches the healthy-run queue commentary in tentura_2no_pg_remediation_probe_test.
const k8xfMinDisposablePgLifecycleLockWait = Duration(minutes: 10);

const _harnessRelative = 'test/support/disposable_pg_target.dart';

const _8xfAcceptanceMarker = 'tentura-8xf acceptance';

void main() {
  group('tentura-8xf disposable pg lifecycle lock timeout', () {
    test('acceptance harness file declares tentura-8xf marker', () {
      final source = _readHarnessSource();
      expect(
        source,
        contains(_8xfAcceptanceMarker),
        reason: 'Alloy tentura-8xf tracking expects the marker in $_harnessRelative',
      );
    });

    test(
      'Env.pgEndpointSettings leaves queryTimeout unset (postgres default 5 minutes)',
      () {
        final settings = Env.test().pgEndpointSettings;
        expect(settings.queryTimeout, isNull);
        expect(
          _resolvedPostgresDefaultQueryTimeout(settings),
          const Duration(minutes: 5),
          reason:
              'unset queryTimeout resolves to five minutes in postgres 3.5.12',
        );
      },
    );

    test(
      'withDisposablePgLifecycleLock does not open the lock session with only '
      'adminEnv.pgEndpointSettings',
      () {
        final block = _withDisposablePgLifecycleLockBlock(_readHarnessSource());
        final usesBareAdminSettings = RegExp(
          r'Connection\.open\(\s*'
          r'adminEnv\.pgEndpoint,\s*'
          r'settings:\s*adminEnv\.pgEndpointSettings,\s*'
          r'\)',
          multiLine: true,
        ).hasMatch(block);
        expect(
          usesBareAdminSettings,
          isFalse,
          reason:
              'bare adminEnv.pgEndpointSettings makes pg_advisory_lock wait '
              'inherit the five-minute client queryTimeout and cancel with '
              'SQLSTATE 57014 under lifecycle-lock contention (tentura-8xf)',
        );
      },
    );

    test(
      'withDisposablePgLifecycleLock configures lock-wait timeout at or above '
      'k8xfMinDisposablePgLifecycleLockWait',
      () {
        final block = _withDisposablePgLifecycleLockBlock(_readHarnessSource());
        final configured = _configuredLifecycleLockWaitTimeout(block);
        expect(
          configured,
          isNotNull,
          reason:
              'expected dedicated ConnectionSettings.queryTimeout or an '
              'execute(timeout: ...) on pg_advisory_lock in '
              'withDisposablePgLifecycleLock',
        );
        expect(
          configured!,
          greaterThanOrEqualTo(k8xfMinDisposablePgLifecycleLockWait),
          reason:
              'parallel pg suites queue on tentura_disposable_pg_lifecycle; '
              'lock wait must outlive the default five-minute cancel window',
        );
      },
    );
  });
}

String _readHarnessSource() {
  for (final root in const ['.', '../../packages/server']) {
    final file = File('$root/$_harnessRelative');
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('$_harnessRelative not found');
}

String _withDisposablePgLifecycleLockBlock(String source) {
  const signature = 'Future<T> withDisposablePgLifecycleLock<T>';
  final start = source.indexOf(signature);
  expect(start, greaterThan(-1), reason: 'missing $signature');
  final braceStart = source.indexOf('{', start);
  expect(braceStart, greaterThan(-1));
  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    final char = source[i];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('unbalanced braces in withDisposablePgLifecycleLock');
}

Duration? _configuredLifecycleLockWaitTimeout(String block) {
  final fromConnection = _parseMaxDurationAfterToken(block, 'queryTimeout:');
  final lockExecute = _pgAdvisoryLockExecuteFragment(block);
  final fromExecute = lockExecute == null
      ? null
      : _parseMaxDurationAfterToken(lockExecute, 'timeout:');
  if (fromConnection == null && fromExecute == null) {
    return null;
  }
  if (fromConnection == null) {
    return fromExecute;
  }
  if (fromExecute == null) {
    return fromConnection;
  }
  return fromConnection > fromExecute ? fromConnection : fromExecute;
}

String? _pgAdvisoryLockExecuteFragment(String block) {
  const needle = 'pg_advisory_lock(hashtext(@key))';
  final index = block.indexOf(needle);
  if (index < 0) {
    return null;
  }
  final executeStart = block.lastIndexOf('execute(', index);
  if (executeStart < 0) {
    return null;
  }
  final closing = block.indexOf(');', index);
  if (closing < 0) {
    return null;
  }
  return block.substring(executeStart, closing + 2);
}

Duration? _parseMaxDurationAfterToken(String text, String token) {
  Duration? max;
  var searchFrom = 0;
  while (true) {
    final index = text.indexOf(token, searchFrom);
    if (index < 0) {
      return max;
    }
    final slice = text.substring(index + token.length);
    final match = RegExp(
      r'^\s*const\s+Duration\(\s*'
      r'(hours:\s*(\d+))?(?:,\s*)?'
      r'(minutes:\s*(\d+))?(?:,\s*)?'
      r'(seconds:\s*(\d+))?'
      r'\s*\)',
    ).firstMatch(slice);
    if (match != null) {
      final hours = int.tryParse(match.group(2) ?? '') ?? 0;
      final minutes = int.tryParse(match.group(4) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(6) ?? '') ?? 0;
      final duration = Duration(hours: hours, minutes: minutes, seconds: seconds);
      if (max == null || duration > max) {
        max = duration;
      }
    }
    searchFrom = index + token.length;
  }
}

/// Mirrors postgres resolved_settings.dart default when queryTimeout is unset.
Duration _resolvedPostgresDefaultQueryTimeout(ConnectionSettings settings) =>
    settings.queryTimeout ?? const Duration(minutes: 5);
