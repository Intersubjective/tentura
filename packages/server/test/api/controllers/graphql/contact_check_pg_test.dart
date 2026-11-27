@Tags(['pg', 'multi-connection'])
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_wait.dart';
import '../../../support/session_database_di_harness.dart';

const _caller = 'U0123456789a0';
const _otherCaller = 'U0123456789a1';
const _alice = 'U0123456789a2';
const _bob = 'U0123456789a3';
const _carol = 'U0123456789a4';
const _diane = 'U0123456789a5';
const _aliceEmail = 'alice@example.com';
const _bobEmail = 'bob@example.com';
const _carolEmail = 'carol@example.com';
const _dianeEmail = 'diane@example.com';
const _unknownEmail = 'absent@example.com';
const _origin = 'http://127.0.0.1:2080';
const _today = "(now() AT TIME ZONE 'UTC')::date";
const _oldKey = 'contact-check-old-key';
const _newKey = 'contact-check-new-key';
const _check = r'''
mutation CheckContact($kind: String!, $value: String!) {
  contactCheck(kind: $kind, value: $value) { alreadyOnTentura }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONTACT_CHECK_TEST_DB',
    defaultNamePrefix: 'tentura_test_contact_check',
  );
  final skip = await pgSkipReason(target);

  group('Checking whether an email is already on Tentura', () {
    late Connection writer;
    late _ContactApi api;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      writer = session.writer;
      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse(_origin),
        publicOrigin: _origin,
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 4,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        contactMatchHmacKeys: '1:$_oldKey,2:$_newKey',
      );
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      await configureSessionDatabaseTestGraph(env);
      final auth = getIt<AuthCase>();
      api = _ContactApi(
        getIt<AuthMiddleware>().extractJwtClaims(
          getIt<GraphqlController>().handler,
        ),
        {
          for (final caller in [_caller, _otherCaller])
            caller: auth.issueAccessToken(caller).rawToken,
        },
      );
    });

    setUp(() async {
      await writer.execute('TRUNCATE TABLE public."user" CASCADE');
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
SELECT id, id, 'key-' || id
FROM unnest(ARRAY['$_caller', '$_otherCaller', '$_alice', '$_bob', '$_carol', '$_diane']) AS id
''');
      await writer.execute('''
INSERT INTO public.user_privacy_setting (user_id, enabled)
VALUES ('$_alice', true), ('$_bob', false)
''');
      await _verifyEmail(writer, _alice, _aliceEmail);
      await _verifyEmail(writer, _bob, _bobEmail);
      await _verifyEmail(writer, _carol, _carolEmail);
      await _verifyEmail(writer, _diane, _dianeEmail, olderKey: true);
    });

    Future<List<Object?>> usage({
      String caller = _caller,
      int daysAgo = 0,
    }) async {
      final table = await writer.execute(
        "SELECT to_regclass('public.contact_check_usage') IS NOT NULL",
      );
      // Before the quota migration there are no persisted checks to count.
      if (table.single.single == false) return [];
      final rows = await writer.execute(
        Sql.named('''
SELECT count FROM public.contact_check_usage
WHERE user_id = @caller AND day = $_today - @daysAgo::int
'''),
        parameters: {'caller': caller, 'daysAgo': daysAgo},
      );
      return rows.map((row) => row.single).toList();
    }

    Future<void> spendChecks(int count) async {
      for (var check = 1; check <= count; check++) {
        _expectMatch(
          await api.check(_unknownEmail),
          false,
          reason: 'Check $check',
        );
      }
    }

    test('a verified email matches when discoverability is ON', () async {
      _expectMatch(await api.check(_aliceEmail), true);
    });

    test('a verified email is hidden when discoverability is OFF', () async {
      _expectMatch(await api.check(_bobEmail), false);
    });

    test('an untouched discoverability setting defaults to ON', () async {
      final preference = await writer.execute('''
SELECT enabled FROM public.user_privacy_setting WHERE user_id = '$_carol'
''');
      expect(preference, isEmpty);
      _expectMatch(await api.check(_carolEmail), true);
    });

    test('surrounding spaces and letter case do not change a match', () async {
      _expectMatch(await api.check('  Alice@Example.COM '), true);
    });

    test('emails hashed before key rotation still match', () async {
      _expectMatch(await api.check(_dianeEmail), true);
    });

    test(
      'a match creates no attention event for the matched account',
      () async {
        final before = await _attentionFor(writer, _alice);

        _expectMatch(await api.check(_aliceEmail), true);

        expect(await _attentionFor(writer, _alice), before);
      },
    );

    test('an unknown email returns false and uses one check', () async {
      expect(await usage(), isEmpty);

      _expectMatch(await api.check(_unknownEmail), false);

      expect(await usage(), [1]);
    });

    test('a phone check returns an error and uses no checks', () async {
      _expectMatch(await api.check(_aliceEmail), true);
      expect(await usage(), [1]);

      _expectNoAnswer(await api.check('+12025550100', kind: 'phone'));

      expect(await usage(), [1]);
    });

    test(
      'the daily counter stops at 200 and the next match is refused',
      () async {
        await spendChecks(200);
        expect(await usage(), [200]);

        _expectRateLimited(await api.check(_aliceEmail));

        expect(await usage(), [200]);
      },
    );

    test('overlapping checks cannot exceed the daily quota', () async {
      await spendChecks(199);
      expect(await usage(), [199]);

      // Both addresses match, so a refused request must withhold the answer.
      final replies = await Future.wait([
        api.check(_aliceEmail),
        api.check(_carolEmail),
      ]).timeout(kCompletionWait);

      final answered = replies.where((body) => body['errors'] == null);
      final refused = replies.where((body) => body['errors'] != null);
      expect(
        answered,
        hasLength(lessThanOrEqualTo(1)),
        reason: jsonEncode(replies),
      );
      for (final body in answered) {
        _expectMatch(body, true);
      }
      refused.forEach(_expectNoAnswer);
      expect(await usage(), [199 + answered.length]);
    });

    test('another account can check after the caller reaches 200', () async {
      await spendChecks(200);
      expect(await usage(), [200]);

      _expectMatch(await api.check(_aliceEmail, caller: _otherCaller), true);

      expect(await usage(caller: _otherCaller), [1]);
      expect(await usage(), [200]);
    });

    test('yesterday’s full quota leaves a fresh quota today', () async {
      await spendChecks(1);
      expect(await usage(), [1]);
      final moved = await writer.execute('''
UPDATE public.contact_check_usage SET day = $_today - 1, count = 200
WHERE user_id = '$_caller' AND day = $_today
''');
      expect(moved.affectedRows, 1);
      expect(await usage(), isEmpty);

      _expectMatch(await api.check(_aliceEmail), true);

      expect(await usage(), [1]);
      expect(await usage(daysAgo: 1), [200]);
    });

    test(
      'reaching the daily quota warns once without exposing emails',
      () async {
        final root = Logger.root;
        final previousLevel = root.level;
        root.level = Level.WARNING;
        addTearDown(() => root.level = previousLevel);
        final warnings = <LogRecord>[];
        // The production server log sink takes records from this stream,
        // including records sent by named loggers.
        final subscription = root.onRecord
            .where((record) => record.level == Level.WARNING)
            .listen(warnings.add);
        addTearDown(subscription.cancel);
        final quotaReachedEvent = RegExp(
          r'\bcontact_check_daily_limit_reached\b',
        );
        final alerts = warnings.where(
          (record) => quotaReachedEvent.hasMatch(record.message),
        );

        await spendChecks(199);
        expect(await usage(), [199]);
        expect(alerts, isEmpty);

        _expectMatch(await api.check(_aliceEmail), true);
        expect(await usage(), [200]);
        expect(alerts, hasLength(1), reason: 'Server warnings: $warnings');
        _expectRateLimited(await api.check(_aliceEmail));
        expect(alerts, hasLength(1), reason: 'Server warnings: $warnings');
        final alert = alerts.single;
        final line = '${alert.loggerName}: ${alert.message}';
        expect(line, contains(_caller));
        expect(
          '$line ${alert.error ?? ''}'.toLowerCase(),
          allOf(isNot(contains(_aliceEmail)), isNot(contains(_unknownEmail))),
        );
      },
    );

    group('Importing contacts', () {
      test(
        'each saved row reports its own email match, when checked',
        () async {
          final before = await _attentionFor(writer, _alice);

          final body = await api.importContacts('''
  {name: "Alice", email: "$_aliceEmail"},
  {name: "Bob", email: "$_bobEmail"},
  {name: "Carol", email: "$_carolEmail"},
  {name: "Unknown account", email: "$_unknownEmail"},
  {name: "No email"}
''');
          _expectCreated(body, await _savedContacts(writer), {
            'Alice': true,
            'Bob': false,
            'Carol': true,
            'Unknown account': false,
            'No email': null,
          });

          expect(await _attentionFor(writer, _alice), before);
        },
      );

      test(
        'three imported emails use three checks from the caller’s quota',
        () async {
          expect(await usage(), isEmpty);

          final body = await api.importContacts('''
  {name: "Alice", email: "$_aliceEmail"},
  {name: "Bob", email: "$_bobEmail"},
  {name: "Unknown account", email: "$_unknownEmail"},
  {name: "No email"}
''', includeMatch: false);
          expect(
            _result(body, 'phantomCreateBatch'),
            allOf(
              containsPair('created', hasLength(4)),
              containsPair('refused', isEmpty),
            ),
          );

          expect(await usage(), [3]);
        },
      );

      test(
        'imports still save contacts after the shared quota runs out',
        () async {
          await spendChecks(199);
          expect(await usage(), [199]);

          final body = await api.importContacts('''
  {name: "Alice", email: "$_aliceEmail"},
  {name: "Carol", email: "$_carolEmail"},
  {name: "Unknown account", email: "$_unknownEmail"}
''');
          final saved = await _savedContacts(writer);
          _expectCreated(body, saved, {
            'Alice': true,
            'Carol': null,
            'Unknown account': null,
          });
          expect(await usage(), [200]);
          _expectRateLimited(await api.check(_aliceEmail));

          final laterImport = await api.importContacts('''
  {name: "Diane", email: "$_dianeEmail"}
''');
          _expectCreated(
            laterImport,
            await _savedContacts(writer),
            {'Diane': null},
            previouslySaved: saved,
          );
          expect(await usage(), [200]);
        },
      );
    });
  }, skip: skip);
}

Future<void> _verifyEmail(
  Connection writer,
  String account,
  String email, {
  bool olderKey = false,
}) async {
  final key = olderKey ? _oldKey : _newKey;
  final digest = Hmac(sha256, utf8.encode(key)).convert(utf8.encode(email));
  await writer.execute(
    Sql.named('''
INSERT INTO public.account_verified_contact
  (id, account_id, kind, value, last_source, match_hmac, hmac_key_version)
VALUES (@id, @account, 'email', @email, 'email', decode(@digest, 'hex'), @version)
'''),
    parameters: {
      'id': 'V${account.substring(1)}',
      'account': account,
      'email': email,
      'digest': digest.toString(),
      'version': olderKey ? 1 : 2,
    },
  );
}

Future<List<List<Object?>>> _attentionFor(
  Connection writer,
  String account,
) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT 'occurrence', occurrence_id FROM public.attention_occurrence_recipient
WHERE account_id = @account
UNION ALL
SELECT 'outbox', id FROM public.notification_outbox WHERE account_id = @account
ORDER BY 1, 2
'''),
    parameters: {'account': account},
  );
  return rows.map((row) => row.toList()).toList();
}

Object? _result(Map<String, Object?> body, String field, {String? reason}) {
  expect(
    body['errors'],
    isNull,
    reason: '${reason ?? field}: ${jsonEncode(body)}',
  );
  expect(body['data'], contains(field));
  return (body['data']! as Map<String, Object?>)[field];
}

void _expectMatch(Map<String, Object?> body, bool matched, {String? reason}) {
  expect(_result(body, 'contactCheck', reason: reason), {
    'alreadyOnTentura': matched,
  });
}

void _expectNoAnswer(Map<String, Object?> body) {
  expect(body['errors'], isNotEmpty, reason: jsonEncode(body));
  final data = body['data'] as Map<String, Object?>?;
  expect(data?['contactCheck'], isNull, reason: jsonEncode(body));
}

void _expectRateLimited(Map<String, Object?> body) {
  _expectNoAnswer(body);
  final code = const RateLimitedException().code.codeNumber;
  expect(body['errors'], [
    containsPair('extensions', containsPair('code', '$code')),
  ]);
}

Future<Map<String, String>> _savedContacts(Connection writer) async {
  final rows = await writer.execute('''
SELECT display_name, id FROM public.phantom WHERE owner_id = '$_caller'
''');
  return {for (final row in rows) row[0]! as String: row[1]! as String};
}

void _expectCreated(
  Map<String, Object?> body,
  Map<String, String> saved,
  Map<String, bool?> answers, {
  Map<String, String> previouslySaved = const {},
}) {
  final result = _result(
    body,
    'phantomCreateBatch',
    reason: 'Saved contacts: ${saved.keys.join(', ')}',
  );
  expect(saved, {
    ...previouslySaved,
    for (final name in answers.keys) name: isA<String>(),
  });
  expect(result, {
    'created': unorderedEquals([
      for (final (index, answer) in answers.entries.indexed)
        {
          'rowIndex': index,
          'id': saved[answer.key],
          'alreadyOnTentura': answer.value,
        },
    ]),
    'refused': isEmpty,
  });
}

final class _ContactApi {
  const _ContactApi(this._handler, this._tokens);

  final Handler _handler;
  final Map<String, String> _tokens;

  Future<Map<String, Object?>> check(
    String value, {
    String kind = 'email',
    String caller = _caller,
  }) => _post(_check, {'kind': kind, 'value': value}, caller);

  Future<Map<String, Object?>> importContacts(
    String rows, {
    bool includeMatch = true,
  }) => _post(
    '''
mutation ImportContacts {
  phantomCreateBatch(rows: [$rows], keepContacts: false) {
    created { rowIndex id ${includeMatch ? 'alreadyOnTentura' : ''} }
    refused { rowIndex message }
  }
}
''',
    const {},
    _caller,
  );

  Future<Map<String, Object?>> _post(
    String query,
    Map<String, Object?> variables,
    String caller,
  ) async {
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('$_origin$kPathGraphQLEndpointV2'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${_tokens[caller]}',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }
}
