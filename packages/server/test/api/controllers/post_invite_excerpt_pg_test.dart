@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/invite_preview_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts.dart' show kInvitationTTL;
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Uexcerptauth01';
const _outsider = 'Uexcerptouts01';
const _post = 'Bexcerptpost01';
const _request = 'Bexcerptreq001';
const _root = 'Mexcerptroot01';
const _postInvite = 'Iexcerptpost01';
const _requestInvite = 'Iexcerptreq001';
const _hiddenInvite = 'Iexcerpthide01';
const _sameTextRequest = 'Bexcerptreq002';
const _sameTextRequestInvite = 'Iexcerptreq002';
const _shortText = 'Q520 post: community garden cleanup…';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_INVITE_EXCERPT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_invite_excerpt',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late Router router;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        publicOrigin: 'http://127.0.0.1:2080',
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    router = Router()
      ..get(
        '/api/v2/invite/<code>/preview',
        getIt<InvitePreviewController>().handler,
      );
  });

  tearDownAll(() async {
    await getIt.reset();
    await tearDownDisposablePgWriter(session: session);
  });

  setUp(() async {
    await writer.execute('''
TRUNCATE TABLE public.invitation, public.beacon_room_message,
  public.beacon, public."user" CASCADE
''');
    for (final (slot, id) in [(1, _author), (2, _outsider)]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {
          'id': id,
          'key': pgTestPublicKey('excerpt', slot),
        },
      );
    }
  });

  Future<Map<String, dynamic>> preview(String code) async {
    final response = await router(
      Request('GET', Uri.parse('http://localhost/api/v2/invite/$code/preview')),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  Future<void> seed(String text) async {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES
  ('$_post', '$_author', '', '', 0, 1, 1, false, now()),
  ('$_request', '$_author', 'Garden request', '  Request description  ',
   0, 0, 1, false, now())
''');
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_root', '$_post', '$_author', @body)
'''),
      parameters: {'body': text},
    );
    await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_root' WHERE id = '$_post'
''');
    await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('Mexcerptreply1', '$_post', '$_author', 'A later discussion message')
''');
    // A Request whose description is the very same text: its preview is the
    // existing clipping contract a Post excerpt has to match.
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at)
VALUES ('$_sameTextRequest', '$_author', 'Same text', @body, 0, 0, 1,
  false, now())
'''),
      parameters: {'body': '  $text  '},
    );
    await writer.execute('''
INSERT INTO public.invitation (id, user_id, beacon_id, created_at, updated_at)
VALUES
  ('$_postInvite', '$_author', '$_post', now(), now()),
  ('$_requestInvite', '$_author', '$_request', now(), now()),
  ('$_sameTextRequestInvite', '$_author', '$_sameTextRequest', now(), now()),
  ('$_hiddenInvite', '$_outsider', '$_post', now(), now())
''');
  }

  group('Post invite preview excerpts', () {
    for (final sample in [
      (
        name: 'short root text is shown in full',
        text: _shortText,
        clipped: false,
      ),
      (
        name: 'long root text is clipped exactly like a Request snippet',
        text: '$_shortText ${'garden cleanup ' * 20}',
        clipped: true,
      ),
    ]) {
      test(sample.name, () async {
        await seed(sample.text);

        // A Request still uses its own description, rather than room text.
        expect((await preview(_requestInvite))['beacon'], {
          'id': _request,
          'kind': 'request',
          'title': 'Garden request',
          'snippet': 'Request description',
          'description': 'Request description',
        });

        // Preview visibility gates the entire Post. Root excerpts use the
        // same content predicate; there is no separate root-text permission.
        final hidden = await preview(_hiddenInvite);
        expect(hidden, isNot(contains('beacon')));
        expect(jsonEncode(hidden), isNot(contains(sample.text.trim())));

        await writer.execute(
          Sql.named('''
UPDATE public.invitation SET created_at = @expiredAt
WHERE id = '$_postInvite'
'''),
          parameters: {
            'expiredAt': DateTime.now()
                .toUtc()
                .subtract(kInvitationTTL)
                .subtract(const Duration(days: 1)),
          },
        );
        final expired = await preview(_postInvite);
        expect(expired['codeStatus'], 'expired');
        expect(expired, isNot(contains('beacon')));
        expect(jsonEncode(expired), isNot(contains(sample.text.trim())));
        await writer.execute('''
UPDATE public.invitation SET created_at = now() WHERE id = '$_postInvite'
''');

        // The Request snippet contract (limit, trimming, ellipsis) as
        // the server already applies it to the same text.
        final reference =
            (await preview(_sameTextRequestInvite))['beacon']!
                as Map<String, dynamic>;
        final referenceSnippet = reference['snippet']! as String;
        final trimmed = sample.text.trim();
        expect(reference['description'], trimmed);
        expect(
          referenceSnippet.length < trimmed.length,
          sample.clipped,
          reason: 'sample must (not) exceed the request snippet limit',
        );

        final visible = await preview(_postInvite);
        expect(visible['codeStatus'], 'available');
        final beacon = visible['beacon']! as Map<String, dynamic>;
        expect(beacon['kind'], 'post');
        expect(beacon['snippet'], isNotEmpty);
        expect(
          (beacon['snippet']! as String).startsWith(
            _shortText.substring(0, 20),
          ),
          isTrue,
        );
        expect(beacon['snippet'], referenceSnippet);
        expect(beacon['description'], trimmed);
      });
    }
  });
}
