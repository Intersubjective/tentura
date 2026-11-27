@Tags(['pg', 'multi-connection'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';

const _bootBudget = Duration(seconds: 40);
final _webWorkerListening = RegExp(r'web server listen \[127\.0\.0\.1:\d+\]');
final _taskWorkerStarted = RegExp('Task worker started at ');

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_MATCH_KEY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_match_key',
  );

  final skipReason = await pgSkipReason(target);

  group('Contact match keys at server startup', () {
    late Connection writer;
    late String kernel;

    setUpAll(() async {
      final temp = await Directory.systemTemp.createTemp(
        'contact_key_startup_',
      );
      addTearDown(() => temp.delete(recursive: true));
      kernel = '${temp.path}/server.dill';
      final compilation = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'bin/tentura.dart',
        '-o',
        kernel,
      ]);
      expect(compilation.exitCode, 0, reason: '${compilation.stderr}');

      final session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      // Model an already initialized graph and suppress its bulk reload in
      // this disposable database. The local MeritRank service is shared.
      await writer.execute('''
UPDATE public.trust_cutover_state
SET status = 'done', ban_walls_at = now()
WHERE id = 1
''');
      await writer.execute('''
CREATE OR REPLACE FUNCTION public.meritrank_init() RETURNS integer
LANGUAGE sql STABLE AS 'SELECT 0'
''');
      // Model persisted contact hashes during rotation, independently of
      // the import and verified-contact writers.
      await writer.execute('''
ALTER TABLE public.account_verified_contact
  ADD COLUMN IF NOT EXISTS match_hmac bytea,
  ADD COLUMN IF NOT EXISTS hmac_key_version smallint
''');
      // The private-contact writer ships separately. The disposable database
      // needs the contact storage shape even when a test leaves it empty.
      await writer.execute('''
CREATE TABLE IF NOT EXISTS public.phantom_contact_point (
  phantom_id text NOT NULL REFERENCES public.phantom(id) ON DELETE CASCADE,
  kind text NOT NULL,
  value text,
  match_hmac bytea,
  hmac_key_version smallint
)
''');
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
    });

    test(
      'starts with no hashes or all keys and refuses to drop the verified-contact key',
      () async {
        await _expectStarts(kernel, target, '1:secretA');
        await _seedContacts(writer);
        await _expectStarts(kernel, target, '1:secretA,2:secretB');
        await _expectMissingKeyRefusal(
          kernel,
          target,
          ring: '2:secretB',
          missingVersion: 1,
        );
      },
    );

    test(
      'accepts keys in descending order and refuses to drop the hash-only contact key',
      () async {
        await _seedContacts(writer);
        await _expectStarts(kernel, target, '2:secretB,1:secretA');
        await _expectMissingKeyRefusal(
          kernel,
          target,
          ring: '1:secretA',
          missingVersion: 2,
        );
      },
    );
  }, skip: skipReason);
}

// Both tables contain a hash on every populated boot. Each key is referenced
// by just one table, so each rejection independently proves that table matters.
Future<void> _seedContacts(Connection writer) async {
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Ucontactkeys1', 'Contact key owner', 'pk-contact-keys')
''');
  await writer.execute(
    Sql.named('''
INSERT INTO public.account_verified_contact
  (id, account_id, kind, value, last_source, match_hmac, hmac_key_version)
VALUES ('VCcontactkey1', 'Ucontactkeys1', 'email', 'alice@example.com', 'email', @hash, 1)
'''),
    parameters: {'hash': _fixtureHash('alice@example.com', 'secretA')},
  );
  await writer.executeWithOwnerScopes(
    ['Ucontactkeys1'],
    '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES ('PH0123456789ab', 'Ucontactkeys1', 'Bob')
''',
  );
  await writer.executeWithOwnerScopes(
    ['Ucontactkeys1'],
    Sql.named('''
INSERT INTO public.phantom_contact_point
  (phantom_id, kind, value, match_hmac, hmac_key_version)
VALUES ('PH0123456789ab', 'email', NULL, @hash, 2)
'''),
    parameters: {'hash': _fixtureHash('bob@example.com', 'secretB')},
  );
}

List<int> _fixtureHash(String email, String secret) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(email)).bytes;

Future<void> _expectStarts(
  String kernel,
  DisposablePgTarget target,
  String ring,
) async {
  final (exitCode, output) = await _boot(kernel, target, ring);
  expect(exitCode, isNull, reason: output);
  expect(output, matches(_webWorkerListening));
  expect(output, matches(_taskWorkerStarted));
}

Future<void> _expectMissingKeyRefusal(
  String kernel,
  DisposablePgTarget target, {
  required String ring,
  required int missingVersion,
}) async {
  final (exitCode, output) = await _boot(kernel, target, ring);
  expect(
    exitCode,
    allOf(isNotNull, isNot(0)),
    reason: 'The server should exit before starting either worker.\n$output',
  );
  expect(output, isNot(matches(_webWorkerListening)));
  expect(output, isNot(matches(_taskWorkerStarted)));
  final missingVersionPattern = RegExp('\\b$missingVersion\\b');
  final diagnostic = const LineSplitter()
      .convert(output)
      .where(
        (line) => line.contains('CONTACT_MATCH_HMAC_KEYS'),
      );
  expect(
    diagnostic,
    contains(matches(missingVersionPattern)),
    reason: 'The startup error must identify missing version $missingVersion.',
  );
}

/// Wait for the real CLI to exit or for both workers to report startup.
/// Stop and reap the child in either case, including when startup times out.
Future<(int?, String)> _boot(
  String kernel,
  DisposablePgTarget target,
  String ring,
) async {
  final env = target.databaseEnv;
  final process = await Process.start(
    Platform.resolvedExecutable,
    [kernel],
    includeParentEnvironment: false,
    environment: {
      'ENVIRONMENT': 'dev',
      'SERVER_NAME': 'http://127.0.0.1',
      'IMAGE_SERVER': 'http://127.0.0.1',
      'HOST': '127.0.0.1',
      'PORT': '0',
      'WORKERS_COUNT': '1',
      'TASK_DELAY': '3600',
      'POSTGRES_HOST': env.pgHost,
      'POSTGRES_PORT': '${env.pgPort}',
      'POSTGRES_DBNAME': env.pgDatabase,
      'POSTGRES_USERNAME': env.pgUsername,
      'POSTGRES_PASSWORD': env.pgPassword,
      'CONTACT_MATCH_HMAC_KEYS': ring,
    },
  );
  final output = StringBuffer();
  final ready = Completer<int?>();
  var webStarted = false;
  var taskStarted = false;
  final drained = Future.wait([
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          output.writeln(line);
          webStarted |= _webWorkerListening.hasMatch(line);
          taskStarted |= _taskWorkerStarted.hasMatch(line);
          if (webStarted && taskStarted && !ready.isCompleted) ready.complete();
        }),
    process.stderr.transform(utf8.decoder).forEach(output.write),
  ]);
  int? exitCode;
  try {
    exitCode = await Future.any([process.exitCode, ready.future]).timeout(
      _bootBudget,
      onTimeout: () =>
          fail('Server neither exited nor started both workers.\n$output'),
    );
  } finally {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(const Duration(seconds: 5));
    await drained.timeout(const Duration(seconds: 5));
  }
  return (exitCode, output.toString());
}
