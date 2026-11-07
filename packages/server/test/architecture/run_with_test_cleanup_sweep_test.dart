@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// PG test callbacks can invoke cleanup even inside a bare `dart test`. The
// process sweep is global, so changing the nested TMPDIR alone does not
// protect the outer VM compiler. Exercise that boundary with sleeping
// test-owned processes, not a real compiler or a second Dart test runner.
void main() {
  late Directory runtime;
  late File executable;
  late File procViewLibrary;
  late File publicationLibrary;

  setUpAll(() async {
    expect(
      Platform.isLinux,
      isTrue,
      reason: 'This checks the Linux /proc sweep.',
    );
    runtime = await Directory.systemTemp.createTemp('cleanup-sweep-runtime-');
    addTearDown(() => runtime.delete(recursive: true));
    executable = File('${runtime.path}/process-fixture');
    procViewLibrary = File('${runtime.path}/proc-view.so');
    final source = File(
      'test/support/cleanup_sweep_process_fixture.c',
    ).absolute.path;
    publicationLibrary = File('${runtime.path}/publication-probe.so');
    for (final args in [
      [
        '-O2',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-shared',
        '-fPIC',
        'test/support/cleanup_sweep_publication_probe.c',
        '-ldl',
        '-o',
        publicationLibrary.path,
      ],
      ['-O2', '-Wall', '-Wextra', '-Werror', source, '-o', executable.path],
      [
        '-O2',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-shared',
        '-fPIC',
        '-DCLEANUP_PROC_VIEW',
        source,
        '-ldl',
        '-o',
        procViewLibrary.path,
      ],
    ]) {
      final result = await Process.run('cc', args);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  group('run_with_test_cleanup sweep isolation', () {
    test('nested sweep preserves wrapped compiler in another TMPDIR', () async {
      final outcome = await _sweepRunner(
        executable,
        procViewLibrary,
        wrapped: true,
        separateTmpdir: true,
      );
      _expectHealthySweep(outcome);
      expect(outcome.ownerAlive, isTrue, reason: outcome.diagnostics);
      expect(
        outcome.compilerAlive,
        isTrue,
        reason:
            'A live test runner still owns this compiler even when the '
            'nested wrapper uses a private TMPDIR.\n${outcome.diagnostics}',
      );
      expect(
        outcome.kernel,
        'compiled test kernel',
        reason: outcome.diagnostics,
      );
      expect(outcome.flutterCache, 'test cache', reason: outcome.diagnostics);
    });

    test(
      'sweep preserves a compiler with a live bare Dart test owner',
      () async {
        final outcome = await _sweepRunner(
          executable,
          procViewLibrary,
          wrapped: false,
          separateTmpdir: false,
        );
        _expectHealthySweep(outcome);
        expect(
          outcome.compilerAlive,
          isTrue,
          reason:
              'Absence of a cleanup tag does not make a compiler orphaned. '
              'Real non-pg callbacks can start a sweep inside an unwrapped '
              'runner.\n${outcome.diagnostics}',
        );
        // This cache is explicitly referenced by the live compiler's argv.
        // There is no assertion about an unreferenced bare-runner cache.
        expect(
          outcome.kernel,
          'compiled test kernel',
          reason: outcome.diagnostics,
        );
      },
    );

    test(
      'same-TMPDIR wrapped owner and its referenced cache survive',
      () async {
        final outcome = await _sweepRunner(
          executable,
          procViewLibrary,
          wrapped: true,
          separateTmpdir: false,
        );
        _expectHealthySweep(outcome);
        expect(outcome.compilerAlive, isTrue, reason: outcome.diagnostics);
        expect(
          outcome.kernel,
          'compiled test kernel',
          reason: outcome.diagnostics,
        );
      },
    );

    test('orphaned compiler and dead-owner caches are still swept', () async {
      final outcome = await _sweepRunner(
        executable,
        procViewLibrary,
        wrapped: false,
        separateTmpdir: false,
        liveOwner: false,
      );
      _expectHealthySweep(outcome);
      expect(outcome.compilerAlive, isFalse, reason: outcome.diagnostics);
      expect(outcome.kernel, isNull, reason: outcome.diagnostics);
      expect(outcome.flutterCache, isNull, reason: outcome.diagnostics);
    });
  });

  group('fixture publication through the sweep runner', () {
    Future<Map<String, String>> probe(String marker, String mode) async {
      final records = await Directory.systemTemp.createTemp(
        'publication-pids-',
      );
      addTearDown(() async {
        await for (final entry in records.list()) {
          final processId = int.parse(entry.uri.pathSegments.last);
          if (await _isFixture(processId, executable)) {
            Process.killPid(processId, ProcessSignal.sigkill);
          }
        }
        await records.delete(recursive: true);
      });
      return {
        'LD_PRELOAD': publicationLibrary.path,
        'PUBLICATION_MARKER': marker,
        'PUBLICATION_MODE': mode,
        'PUBLICATION_RECORDS': records.path,
      };
    }

    for (final marker in ['compiler.pid', 'owner.pid']) {
      test('$marker publication preserves the live owner and caches', () async {
        final outcome = await _sweepRunner(
          executable,
          procViewLibrary,
          wrapped: true,
          separateTmpdir: false,
          fixtureEnvironment: await probe(marker, 'transient'),
        );
        _expectHealthySweep(outcome);
        expect(outcome.ownerAlive, isTrue, reason: outcome.diagnostics);
        expect(outcome.compilerAlive, isTrue, reason: outcome.diagnostics);
        expect(
          outcome.kernel,
          'compiled test kernel',
          reason: outcome.diagnostics,
        );
        expect(outcome.flutterCache, 'test cache', reason: outcome.diagnostics);
      });

      test(
        '$marker readiness failure prints the observed whitespace content',
        () async {
          // Whitespace is non-numeric content that the current readiness poll
          // never accepts. Unlike FormatException for a non-empty token, its
          // current timeout diagnostic loses the observed file contents.
          final whitespace = List.generate(
            8 + DateTime.now().microsecond % 13,
            (index) => index.isEven ? ' ' : '\t',
          ).join();
          final content = '$whitespace\n';
          File? observedMarker;
          final environment = await probe(marker, 'persistent');
          environment['PUBLICATION_CONTENT'] = content;
          Object? failure;
          try {
            await _sweepRunner(
              executable,
              procViewLibrary,
              wrapped: true,
              separateTmpdir: false,
              fixtureEnvironment: environment,
              observeMarkers: (compiler, owner) {
                observedMarker = marker == 'compiler.pid' ? compiler : owner;
              },
            );
          } catch (error) {
            failure = error;
          }
          expect(
            failure,
            isNotNull,
            reason: 'An invalid PID must fail readiness.',
          );
          final observed = await observedMarker!.readAsString();
          expect(observed, content);
          final printed = failure.toString();
          expect(
            printed.contains(observed) ||
                printed.contains(jsonEncode(observed)) ||
                printed.contains(
                  jsonEncode(
                    observed,
                  ).substring(1, jsonEncode(observed).length - 1),
                ),
            isTrue,
            reason:
                'Failure must print the actual marker contents, literally or escaped: ${jsonEncode(observed)}; got $printed',
          );
        },
      );
    }

    test(
      'client cache sweep preserves live PID markers and referenced temporary files',
      () async {
        // Establish full-wrapper cache isolation with ordinary publication
        // first, then demand the same outcome when publication overlaps reads.
        for (final environment in [
          <String, String>{},
          await probe('compiler.pid', 'transient'),
        ]) {
          final outcome = await _sweepRunner(
            executable,
            procViewLibrary,
            wrapped: false,
            separateTmpdir: false,
            fixtureEnvironment: environment,
            checkClientCacheSweep: true,
          );
          _expectHealthySweep(outcome);
          expect(outcome.ownerAlive, isTrue, reason: outcome.diagnostics);
          expect(outcome.compilerAlive, isTrue, reason: outcome.diagnostics);
          expect(
            outcome.kernel,
            'compiled test kernel',
            reason: outcome.diagnostics,
          );
          expect(
            outcome.flutterCache,
            'test cache',
            reason: outcome.diagnostics,
          );
        }
      },
    );
  });
}

void _expectHealthySweep(_Outcome outcome) {
  expect(outcome.exitCode, 0, reason: outcome.diagnostics);
  expect(outcome.diagnostics, isNot(contains('Traceback')));
  expect(outcome.diagnostics, isNot(contains('fixture signal sandbox')));
}

typedef _Outcome = ({
  int exitCode,
  bool ownerAlive,
  bool compilerAlive,
  String? kernel,
  String? flutterCache,
  String diagnostics,
});

Future<_Outcome> _sweepRunner(
  File executable,
  File procViewLibrary, {
  required bool wrapped,
  required bool separateTmpdir,
  bool liveOwner = true,
  Map<String, String> fixtureEnvironment = const {},
  bool checkClientCacheSweep = false,
  void Function(File compiler, File owner)? observeMarkers,
}) async {
  final scratch = await Directory.systemTemp.createTemp('cleanup-sweep-');
  addTearDown(() => scratch.delete(recursive: true));
  final outerTmp = await Directory('${scratch.path}/owner-tmp').create();
  final sweepTmp = separateTmpdir
      ? await Directory('${scratch.path}/sweep-tmp').create()
      : outerTmp;
  final procView = await Directory('${scratch.path}/proc-view').create();
  final bin = await Directory('${scratch.path}/bin').create();
  final markerRoot = checkClientCacheSweep ? outerTmp.path : scratch.path;
  final compilerReady = File('$markerRoot/compiler.pid');
  final ownerReady = File('$markerRoot/owner.pid');
  observeMarkers?.call(compilerReady, ownerReady);
  final kernel = await File(
    '${outerTmp.path}/dart_test.kernel.outer/output.dill',
  ).create(recursive: true);
  await kernel.writeAsString('compiled test kernel');
  final flutterCache = await File(
    '${outerTmp.path}/flutter_tools.outer/cache',
  ).create(recursive: true);
  await flutterCache.writeAsString('test cache');
  // Scope this check to process/cache cleanup; never run shared Postgres GC.
  await File('${bin.path}/docker').writeAsString('#!/bin/sh\nexit 1\n');
  final chmod = await Process.run('chmod', ['+x', '${bin.path}/docker']);
  expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

  final environment = Map<String, String>.of(Platform.environment)
    ..remove('TENTURA_TEST_CLEANUP_RUN')
    ..['TMPDIR'] = outerTmp.path
    ..addAll(fixtureEnvironment);
  if (wrapped) {
    environment['TENTURA_TEST_CLEANUP_RUN'] = scratch.path;
  }
  // Kernel-supplied argv/stat/environ are used throughout. Neither PIDs nor
  // Linux stat fields are synthesized, and Python is not replaced or patched.
  final runnerArgv = utf8
      .decode(
        await File('/proc/$pid/cmdline').readAsBytes(),
      )
      .split('\u0000')
      .where((arg) => arg.isNotEmpty)
      .toList();
  final owner = await Process.start(
    executable.path,
    [
      '--start',
      liveOwner ? 'live' : 'orphan',
      kernel.path,
      compilerReady.path,
      ownerReady.path,
      '${File(Platform.resolvedExecutable).parent.path}/snapshots/'
          'frontend_server_aot.dart.snapshot',
      ...runnerArgv,
      // The bare owner explicitly references this cache in the cache-sweep
      // scenario, so both tmp resources have live owners during the sweep.
      if (checkClientCacheSweep) flutterCache.path,
    ],
    environment: environment,
    includeParentEnvironment: false,
  );
  final stdout = owner.stdout.transform(utf8.decoder).join();
  final stderr = owner.stderr.transform(utf8.decoder).join();
  int? compilerId;
  addTearDown(() async {
    compilerId ??= await compilerReady.exists()
        ? int.tryParse((await compilerReady.readAsString()).trim())
        : null;
    if (compilerId != null && await _isFixture(compilerId!, executable)) {
      Process.killPid(compilerId!, ProcessSignal.sigkill);
    }
    if (await _isFixture(owner.pid, executable)) {
      owner.kill(ProcessSignal.sigkill);
    }
    await owner.exitCode.timeout(const Duration(seconds: 5));
    await stdout;
    await stderr;
  });

  final compilerProcessId = await _waitReady(compilerReady);
  compilerId = compilerProcessId;
  await _waitCompiler(compilerProcessId);
  if (liveOwner) {
    expect(await _waitReady(ownerReady), owner.pid);
  } else {
    expect(await owner.exitCode, 0, reason: await stderr);
  }
  final compilerCommand = utf8.decode(
    await File('/proc/$compilerProcessId/cmdline').readAsBytes(),
  );
  expect(compilerCommand, contains('frontend_server'));
  expect(compilerCommand, contains(kernel.path));
  expect(await _isFixture(compilerProcessId, executable), isTrue);
  final childStatus = await File(
    '/proc/$compilerProcessId/stat',
  ).readAsString();
  final parentId = int.parse(
    childStatus.substring(childStatus.lastIndexOf(')') + 2).split(' ')[1],
  );
  expect(parentId == owner.pid, liveOwner);

  for (final processId in [if (liveOwner) owner.pid, compilerProcessId]) {
    await Link('${procView.path}/$processId').create('/proc/$processId');
  }
  var sweepScript = File('../../scripts/run_with_test_cleanup.sh').absolute;
  File? staleClientCache;
  String? compilerBeforeSweep;
  String? ownerBeforeSweep;
  if (checkClientCacheSweep) {
    // Execute the complete, unchanged wrapper in an isolated repository root.
    // Its real build-cache cleanup must run, rather than merely be skipped
    // because a wrapped peer is active. The expired cache proves it ran.
    expect(wrapped, isFalse);
    final isolatedScript = await File(
      '${scratch.path}/cache-root/scripts/run_with_test_cleanup.sh',
    ).create(recursive: true);
    await isolatedScript.writeAsBytes(await sweepScript.readAsBytes());
    sweepScript = isolatedScript;
    staleClientCache = await File(
      '${scratch.path}/cache-root/packages/client/build/pack.dill',
    ).create(recursive: true);
    await staleClientCache.writeAsString('expired client cache');
    await staleClientCache.setLastModified(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    compilerBeforeSweep = await compilerReady.readAsString();
    ownerBeforeSweep = await ownerReady.readAsString();
    expect(int.tryParse(compilerBeforeSweep.trim()), compilerProcessId);
    expect(int.tryParse(ownerBeforeSweep.trim()), owner.pid);
  }
  final result = await Process.run(
    executable.path,
    [
      '--sandbox',
      liveOwner ? '${owner.pid}' : '0',
      '$compilerProcessId',
      'bash',
      sweepScript.path,
      '--sweep-only',
    ],
    environment: {
      ...environment,
      'TMPDIR': sweepTmp.path,
      // The proc view below hides this suite's own runner, so the sweep
      // would take the real /tmp kernels (CI keeps them there) for leftovers.
      'TENTURA_TEST_CLEANUP_SYSTEM_TMP': sweepTmp.path,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'LD_PRELOAD': procViewLibrary.path,
      'CLEANUP_SWEEP_PROC_VIEW': procView.path,
    }..remove('TENTURA_TEST_CLEANUP_RUN'),
    includeParentEnvironment: false,
  );
  if (checkClientCacheSweep) {
    expect(staleClientCache, isNotNull);
    expect(
      await staleClientCache!.exists(),
      isFalse,
      reason: '${result.stdout}\n${result.stderr}',
    );
    expect(await compilerReady.readAsString(), compilerBeforeSweep);
    expect(await ownerReady.readAsString(), ownerBeforeSweep);
    expect(await kernel.readAsString(), 'compiled test kernel');
    expect(await flutterCache.readAsString(), 'test cache');
  }
  return (
    exitCode: result.exitCode,
    ownerAlive: liveOwner && await _isFixture(owner.pid, executable),
    compilerAlive: await _isFixture(compilerProcessId, executable),
    kernel: await kernel.exists() ? await kernel.readAsString() : null,
    flutterCache: await flutterCache.exists()
        ? await flutterCache.readAsString()
        : null,
    diagnostics: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
}

Future<int> _waitReady(File marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final content = marker.existsSync() ? await marker.readAsString() : null;
    final processId = content == null ? null : int.tryParse(content.trim());
    if (processId != null && processId > 0) return processId;
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Process fixture failed to become ready: ${marker.path}; '
        'content: ${jsonEncode(content)}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitCompiler(int processId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final argv = utf8
        .decode(
          await File('/proc/$processId/cmdline').readAsBytes(),
        )
        .split('\u0000');
    if (argv.contains('--standin-compiler')) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('Sleeping compiler fixture failed to start: $processId');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<bool> _isFixture(int processId, File executable) async {
  try {
    return await Link('/proc/$processId/exe').target() == executable.path;
  } on FileSystemException {
    return false;
  }
}
