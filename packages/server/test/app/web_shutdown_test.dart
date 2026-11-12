import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _shutdownBudget = Duration(seconds: 5);

void main() {
  group(
    'Test web server shutdown',
    () {
      for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
        test(
          '${signal.name} stops the worker before the entrypoint exits',
          () async {
            final child = await _Child.start('entrypoint');
            expect(child.process.kill(signal), isTrue);
            final code = await child.process.exitCode.timeout(_shutdownBudget);
            await child.drained.timeout(_shutdownBudget);
            expect(code, 0, reason: child.output);
            expect(
              child.lines,
              contains(matches(r' stoped at \d{4}-\d{2}-\d{2}[ T]\d{2}:')),
              reason:
                  'The worker must run shutdown before exit(0).\n${child.output}',
            );
            await _expectClosed(child.address, child.port);
          },
        );

        test(
          '${signal.name} closes the server before runWithTestEnv returns',
          () async {
            final child = await _Child.start('return');
            expect(child.process.kill(signal), isTrue);
            final returned = await child.returned.future.timeout(
              _shutdownBudget,
            );
            expect(
              returned,
              'APP_RETURNED:port-closed',
              reason:
                  'Returning must await the worker closing its server.\n'
                  '${child.output}',
            );
            await _expectClosed(child.address, child.port);
            expect(
              child.lines.takeWhile(
                (line) => !line.startsWith('APP_RETURNED:'),
              ),
              contains(matches(r' stoped at \d{4}-\d{2}-\d{2}[ T]\d{2}:')),
              reason: 'Worker shutdown must precede the return.',
            );
          },
        );
      }

      test(
        'runWithTestEnv waits for worker dependency cleanup to finish',
        () async {
          final child = await _Child.start('barrier');
          expect(child.process.kill(), isTrue);
          final first = await Future.any([
            child.disposing.future.then((_) => 'disposing'),
            child.returned.future.then((_) => 'returned'),
          ]).timeout(_shutdownBudget);
          expect(
            first,
            'disposing',
            reason:
                'The app must send stop to the worker and await cleanup.\n'
                '${child.output}',
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            child.returned.isCompleted,
            isFalse,
            reason: 'Cleanup is held, so the worker has not acknowledged stop.',
          );
          child.process.stdin.writeln('release');
          expect(
            await child.returned.future.timeout(_shutdownBudget),
            'APP_RETURNED:port-closed',
          );
          expect(
            child.lines,
            contains('DISPOSAL_FINISHED'),
            reason: 'Cleanup must finish, not merely start, before return.',
          );
          expect(
            child.lines.indexOf('DISPOSAL_FINISHED'),
            lessThan(child.lines.indexOf('APP_RETURNED:port-closed')),
          );
        },
      );

      // bin/test.dart calls exit(0), which hides open ReceivePorts. Exercise the
      // very same App method without forced exit for each supported signal.
      for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
        test(
          '${signal.name} releases ports so the app exits naturally',
          () async {
            final child = await _Child.start('return');
            expect(child.process.kill(signal), isTrue);
            await child.returned.future.timeout(_shutdownBudget);
            final code = await child.process.exitCode.timeout(
              _shutdownBudget,
              onTimeout: () => fail(
                'App returned but remains alive: worker and '
                'runner ports must close.\n${child.output}',
              ),
            );
            await child.drained.timeout(_shutdownBudget);
            expect(code, 0, reason: child.output);
            expect(child.lines, contains('APP_RETURNED:port-closed'));
            expect(
              child.lines,
              contains(matches(r' stoped at \d{4}-\d{2}-\d{2}[ T]\d{2}:')),
            );
          },
        );
      }
    },
    skip: Platform.isLinux
        ? false
        : 'Requires Linux signal masks and ECONNREFUSED.',
  );
}

Future<void> _expectClosed(String address, int port) async {
  await expectLater(
    () async {
      final socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
    },
    throwsA(
      isA<SocketException>().having(
        (error) => error.osError?.errorCode,
        'ECONNREFUSED',
        111,
      ),
    ),
  );
}

final class _Child {
  _Child(this.process) {
    drained = Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            lines.add(line);
            if (line == 'DISPOSAL_STARTED' && !disposing.isCompleted) {
              disposing.complete();
            }
            final listen = RegExp(
              r'web server listen \[([^:\]]+):(\d+)\]',
            ).firstMatch(line);
            if (listen != null && !ready.isCompleted) {
              address = listen.group(1)!;
              port = int.parse(listen.group(2)!);
              ready.complete();
            }
            if (line.startsWith('APP_RETURNED:') && !returned.isCompleted) {
              returned.complete(line);
            }
          }),
      process.stderr.transform(utf8.decoder).forEach(errors.write),
    ]);
  }

  final Process process;
  late final String address;
  late final int port;
  final lines = <String>[];
  final errors = StringBuffer();
  final ready = Completer<void>();
  final disposing = Completer<void>();
  final returned = Completer<String>();
  late final Future<void> drained;
  String get output => '${lines.join('\n')}\nstderr: $errors';

  Future<void> waitForSignalHandlers() async {
    // The Dart VM installs each native signal handler when watch().first
    // subscribes (SDK _SignalController._listen). Reading the child's actual
    // caught-signal mask avoids installing a competing test listener or
    // assuming that a listening socket implies signal readiness.
    final required =
        (1 << (ProcessSignal.sigint.signalNumber - 1)) |
        (1 << (ProcessSignal.sigterm.signalNumber - 1));
    final clock = Stopwatch()..start();
    while (clock.elapsed < _shutdownBudget) {
      final status = await File('/proc/${process.pid}/status').readAsString();
      final caught = RegExp(
        r'^SigCgt:\s+([0-9a-fA-F]+)$',
        multiLine: true,
      ).firstMatch(status);
      if (caught != null &&
          (int.parse(caught.group(1)!, radix: 16) & required) == required) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Runner did not install both SIGINT and SIGTERM handlers.\n$output');
  }

  static Future<_Child> start(String mode) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', 'test/support/web_shutdown_child.dart', mode],
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH']!,
        'HOME': Platform.environment['HOME']!,
        'PUB_CACHE':
            Platform.environment['PUB_CACHE'] ??
            '${Platform.environment['HOME']}/.pub-cache',
        'HOST': '127.0.0.1',
        // The worker asks the OS for an ephemeral port and reports the actual
        // bound port. No reserve-close-bind window can steal this address.
        'PORT': '0',
        'SERVER_NAME': 'http://127.0.0.1',
        'IMAGE_SERVER': 'http://127.0.0.1',
      },
    );
    final child = _Child(process);
    addTearDown(() async {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(_shutdownBudget);
      await child.drained.timeout(_shutdownBudget);
    });
    await child.ready.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('Server never listened.\n${child.output}'),
    );
    await child.waitForSignalHandlers();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(
        Uri.parse('http://${child.address}:${child.port}/'),
      );
      final response = await request.close().timeout(_shutdownBudget);
      expect(
        await utf8.decoder.bind(response).join().timeout(_shutdownBudget),
        'shutdown probe',
      );
      expect(response.statusCode, HttpStatus.ok);
    } finally {
      client.close(force: true);
    }
    return child;
  }
}
