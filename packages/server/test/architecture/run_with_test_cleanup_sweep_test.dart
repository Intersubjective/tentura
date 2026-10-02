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
    for (final args in [
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
}) async {
  final scratch = await Directory.systemTemp.createTemp('cleanup-sweep-');
  addTearDown(() => scratch.delete(recursive: true));
  final outerTmp = await Directory('${scratch.path}/owner-tmp').create();
  final sweepTmp = separateTmpdir
      ? await Directory('${scratch.path}/sweep-tmp').create()
      : outerTmp;
  final procView = await Directory('${scratch.path}/proc-view').create();
  final bin = await Directory('${scratch.path}/bin').create();
  final compilerReady = File('${scratch.path}/compiler.pid');
  final ownerReady = File('${scratch.path}/owner.pid');
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
    ..['TMPDIR'] = outerTmp.path;
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

  await _waitReady(compilerReady);
  final compilerProcessId = int.parse(
    (await compilerReady.readAsString()).trim(),
  );
  compilerId = compilerProcessId;
  await _waitCompiler(compilerProcessId);
  if (liveOwner) {
    await _waitReady(ownerReady);
    expect(int.parse(await ownerReady.readAsString()), owner.pid);
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
  final result = await Process.run(
    executable.path,
    [
      '--sandbox',
      liveOwner ? '${owner.pid}' : '0',
      '$compilerProcessId',
      'bash',
      File('../../scripts/run_with_test_cleanup.sh').absolute.path,
      '--sweep-only',
    ],
    environment: {
      ...environment,
      'TMPDIR': sweepTmp.path,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'LD_PRELOAD': procViewLibrary.path,
      'CLEANUP_SWEEP_PROC_VIEW': procView.path,
    }..remove('TENTURA_TEST_CLEANUP_RUN'),
    includeParentEnvironment: false,
  );
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

Future<void> _waitReady(File marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await marker.exists() ||
      (await marker.readAsString()).trim().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Process fixture failed to become ready: ${marker.path}');
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
