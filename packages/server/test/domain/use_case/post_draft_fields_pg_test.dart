@Tags(['pg', 'repo-files'])
library;

import 'package:graphql_server2/graphql_server2.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';

import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'Updfdauthor1';
const _stranger = 'Updfdstrang1';
const _beacon = 'Bpdfddraft01';
const _requestDraft = 'Bpdfrequest01';
const _draftBody = 'Draft text saved before publish';
const _publishBody = 'Draft text saved before publish';

const _statusDraft = 3;

const _updateDraftDoc = r'''
mutation UpdatePostDraft(
  $id: String!
  $body: String!
  $forwardPolicy: Int!
  $lifetimeHours: Int
) {
  postUpdateDraft(
    id: $id
    body: $body
    forwardPolicy: $forwardPolicy
    lifetimeHours: $lifetimeHours
  ) {
    id
  }
}
''';

const _publishFromSavedDraftDoc = r'''
mutation PublishSavedDraft(
  $id: String!
  $body: String!
  $recipientIds: [String!]!
  $lifetimeHours: Int
) {
  postPublish(
    id: $id
    body: $body
    recipientIds: $recipientIds
    lifetimeHours: $lifetimeHours
  ) {
    beaconId
    rootMessageId
    expiresAt
  }
}
''';

const _publishOmittingDraftFieldsDoc = r'''
mutation PublishOmittingDraftFields(
  $id: String!
  $body: String!
  $recipientIds: [String!]!
) {
  postPublish(id: $id, body: $body, recipientIds: $recipientIds) {
    beaconId
    rootMessageId
    expiresAt
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_DRAFT_FIELDS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_draft_fields',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post draft fields and postUpdateDraft', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late GraphQL schema;
    late PostCase posts;
    late InvitationCase invitations;

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
        ),
      );
      await getIt.allReady(ignorePendingAsyncCreation: true);
      schema = graphqlSchema;
      posts = getIt<PostCase>();
      invitations = getIt<InvitationCase>();
    });

    tearDownAll(() async {
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await writer.execute(
        'TRUNCATE TABLE public.attention_occurrence, '
        'public.notification_outbox, public.beacon_activity_event, '
        'public.beacon, public."user" CASCADE',
      );
      for (final id in [_author, _stranger]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {
            'id': id,
            'key': pgTestPublicKey('pdfddraft', id == _author ? 1 : 2),
          },
        );
      }
      await writer.execute(
        Sql.named('''
          INSERT INTO public.beacon
            (id, user_id, title, description, status, kind, forward_policy,
             is_discoverable)
          VALUES (@id, @author, '', '', @draft, @kind, 1, false)
        '''),
        parameters: {
          'id': _beacon,
          'author': _author,
          'draft': _statusDraft,
          'kind': BeaconKind.post.value,
        },
      );
    });

    Future<Map<String, dynamic>> runGraphql(
      String document,
      Map<String, dynamic> variables, {
      String userId = _author,
    }) async =>
        await schema.parseAndExecute(
              document,
              variableValues: variables,
              globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: userId)},
            )
            as Map<String, dynamic>;

    Future<void> updatePostDraft({
      String body = _draftBody,
      int? forwardPolicy,
      int? lifetimeHours,
    }) async {
      final policy =
          forwardPolicy ?? BeaconForwardPolicyValue.closed.value;
      final data = await runGraphql(_updateDraftDoc, {
        'id': _beacon,
        'body': body,
        'forwardPolicy': policy,
        'lifetimeHours': ?lifetimeHours,
      });
      expect(data['postUpdateDraft'], isNotNull);
    }

    Future<int> beaconSideEffectCount() async =>
        (await writer.execute(
          Sql.named('''
            SELECT
              (SELECT count(*) FROM public.notification_outbox
               WHERE beacon_id = @id)
              + (SELECT count(*) FROM public.attention_occurrence
                 WHERE immutable_payload ->> 'beaconId' = @id)
              + (SELECT count(*) FROM public.beacon_activity_event
                 WHERE beacon_id = @id)
          '''),
          parameters: {'id': _beacon},
        )).single.single! as int;

    Future<bool> canReadContent(String viewerId) async =>
        (await writer.execute(
          Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
          parameters: {'b': _beacon, 'u': viewerId},
        )).single.single! as bool;

    Future<String?> beaconDescription() async =>
        (await writer.execute(
          Sql.named('SELECT description FROM public.beacon WHERE id = @id'),
          parameters: {'id': _beacon},
        )).single.single as String?;

    test(
      'persists draft text, forwarding policy and lifetime on the beacon row',
      () async {
        await updatePostDraft(
          forwardPolicy: BeaconForwardPolicyValue.open.value,
          lifetimeHours: 24,
        );

        final row = (await writer.execute(
          Sql.named('''
            SELECT description, forward_policy, post_lifetime_hours
            FROM public.beacon WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        )).single;
        expect(row[0], _draftBody);
        expect(row[1], BeaconForwardPolicyValue.open.value);
        expect(row[2], 24);
      },
    );

    test(
      'lets the author read the saved draft while a stranger cannot',
      () async {
        await updatePostDraft();

        expect(await canReadContent(_author), isTrue);
        expect(await canReadContent(_stranger), isFalse);
        expect(await beaconDescription(), _draftBody);
      },
    );

    test('rejects postUpdateDraft from a non-owner of the draft', () async {
      await updatePostDraft();

      await expectLater(
        () async {
          try {
            await runGraphql(_updateDraftDoc, {
              'id': _beacon,
              'body': 'Stranger overwrite',
              'forwardPolicy': BeaconForwardPolicyValue.closed.value,
              'lifetimeHours': 24,
            }, userId: _stranger);
          } on ExceptionBase catch (e) {
            expect(e, isA<UnauthorizedException>());
            return;
          }
          fail('postUpdateDraft must reject a non-owner once the draft exists');
        }(),
        completes,
      );
    });

    test('rejects postUpdateDraft after the Post is no longer a draft', () async {
      await posts.publish(
        authorId: _author,
        beaconId: _beacon,
        body: _publishBody,
        mentionUserIds: const [],
        mentionOffsets: const [],
        mentionLengths: const [],
        recipientIds: const [],
        notes: const {},
        forwardPolicy: BeaconForwardPolicyValue.closed,
      );

      await expectLater(
        () async {
          try {
            await runGraphql(_updateDraftDoc, {
              'id': _beacon,
              'body': 'Edit after publish',
              'forwardPolicy': BeaconForwardPolicyValue.closed.value,
            });
          } on ExceptionBase catch (e) {
            expect(e, isA<BeaconCreateException>());
            return;
          }
          fail(
            'postUpdateDraft must reject updates after the Post is published',
          );
        }(),
        completes,
      );
    });

    test(
      'saving the draft emits no notification, attention or activity rows',
      () async {
        final before = await beaconSideEffectCount();
        await updatePostDraft();
        expect(await beaconSideEffectCount(), before);
      },
    );

    test(
      'publish without forwardPolicy keeps the forwarding policy saved on the '
      'draft',
      () async {
        await updatePostDraft(
          forwardPolicy: BeaconForwardPolicyValue.open.value,
          lifetimeHours: 12,
        );

        final data = await runGraphql(_publishFromSavedDraftDoc, {
          'id': _beacon,
          'body': _publishBody,
          'recipientIds': <String>[],
        });
        expect(data['postPublish'], isNotNull);

        final policy = (await writer.execute(
          Sql.named('SELECT forward_policy FROM public.beacon WHERE id = @id'),
          parameters: {'id': _beacon},
        )).single.single! as int;
        expect(policy, BeaconForwardPolicyValue.open.value);
      },
    );

    test(
      'publish applies the draft lifetime at send time, not when the draft '
      'was last edited',
      () async {
        await updatePostDraft(lifetimeHours: 24);
        await writer.execute(
          Sql.named('''
            UPDATE public.beacon
            SET updated_at = updated_at - interval '5 hours'
            WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        );

        final data = await runGraphql(_publishFromSavedDraftDoc, {
          'id': _beacon,
          'body': _publishBody,
          'recipientIds': <String>[],
        });
        final publish = data['postPublish']! as Map<String, dynamic>;
        expect(publish['beaconId'], _beacon);

        final expiryCheck = (await writer.execute(
          Sql.named('''
            SELECT expires_at = published_at + make_interval(hours => 24)
            FROM public.beacon WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        )).single.single! as bool;
        expect(expiryCheck, isTrue);
      },
    );

    test(
      'PostCase.publish without lifetimeHours applies the draft lifetime at '
      'send time',
      () async {
        await updatePostDraft(lifetimeHours: 6);

        await posts.publish(
          authorId: _author,
          beaconId: _beacon,
          body: _publishBody,
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.closed,
        );

        final expiryCheck = (await writer.execute(
          Sql.named('''
            SELECT expires_at = published_at + make_interval(hours => 6)
            FROM public.beacon WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        )).single.single! as bool;
        expect(expiryCheck, isTrue);
      },
    );

    test(
      'after publish the description is empty, draft lifetime is cleared and '
      'the root message holds the text',
      () async {
        await updatePostDraft(lifetimeHours: 6);

        final published = await posts.publish(
          authorId: _author,
          beaconId: _beacon,
          body: _publishBody,
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.closed,
        );

        final beacon = (await writer.execute(
          Sql.named('''
            SELECT description, post_lifetime_hours, post_root_message_id
            FROM public.beacon WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        )).single;
        expect(beacon[0], isEmpty);
        expect(beacon[1], isNull);
        expect(beacon[2], published.rootMessageId);

        final rootBody = (await writer.execute(
          Sql.named('SELECT body FROM public.beacon_room_message WHERE id = @id'),
          parameters: {'id': published.rootMessageId},
        )).single.single! as String;
        expect(rootBody, _publishBody);
      },
    );

    test(
      'postPublish without lifetimeHours applies the draft lifetime saved on '
      'the beacon row',
      () async {
        await updatePostDraft(lifetimeHours: 6);

        final data = await runGraphql(_publishOmittingDraftFieldsDoc, {
          'id': _beacon,
          'body': _publishBody,
          'recipientIds': <String>[],
        });
        expect(data['postPublish'], isNotNull);

        final expiryCheck = (await writer.execute(
          Sql.named('''
            SELECT expires_at = published_at + make_interval(hours => 6)
            FROM public.beacon WHERE id = @id
          '''),
          parameters: {'id': _beacon},
        )).single.single! as bool;
        expect(expiryCheck, isTrue);
      },
    );

    for (final invalid in [0, BeaconPostLifetime.maxHours + 1]) {
      test(
        'rejects postUpdateDraft when lifetimeHours is $invalid',
        () async {
          await expectLater(
            () async {
              try {
                await runGraphql(_updateDraftDoc, {
                  'id': _beacon,
                  'body': _draftBody,
                  'forwardPolicy': BeaconForwardPolicyValue.closed.value,
                  'lifetimeHours': invalid,
                });
              } on ExceptionBase catch (e) {
                expect(e, isA<PostLifetimeInvalidException>());
                return;
              }
              fail('postUpdateDraft must reject out-of-range lifetime hours');
            }(),
            completes,
          );
        },
      );
    }

    test(
      'rejects postUpdateDraft on a Request draft beacon',
      () async {
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon
              (id, user_id, title, description, status, kind, forward_policy,
               is_discoverable)
            VALUES (@id, @author, '', '', @draft, @kind, 1, false)
          '''),
          parameters: {
            'id': _requestDraft,
            'author': _author,
            'draft': _statusDraft,
            'kind': BeaconKind.request.value,
          },
        );

        await expectLater(
          () async {
            try {
              await runGraphql(_updateDraftDoc, {
                'id': _requestDraft,
                'body': _draftBody,
                'forwardPolicy': BeaconForwardPolicyValue.closed.value,
                'lifetimeHours': 24,
              });
            } on ExceptionBase catch (e) {
              expect(e, isA<BeaconCreateException>());
              return;
            }
            fail('postUpdateDraft must apply only to Post drafts');
          }(),
          completes,
        );
      },
    );

    test(
      'rejects out-of-range post_lifetime_hours on a Post draft in the '
      'database',
      () async {
        await updatePostDraft(lifetimeHours: 24);

        await expectLater(
          writer.execute(
            Sql.named('''
              UPDATE public.beacon SET post_lifetime_hours = @hours
              WHERE id = @id
            '''),
            parameters: {'id': _beacon, 'hours': 0},
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
      },
    );

    test(
      'rejects post_lifetime_hours on a Request draft in the database',
      () async {
        await writer.execute(
          Sql.named('''
            INSERT INTO public.beacon
              (id, user_id, title, description, status, kind, forward_policy,
               is_discoverable)
            VALUES (@id, @author, '', '', @draft, @kind, 1, false)
          '''),
          parameters: {
            'id': _requestDraft,
            'author': _author,
            'draft': _statusDraft,
            'kind': BeaconKind.request.value,
          },
        );

        await expectLater(
          writer.execute(
            Sql.named('''
              UPDATE public.beacon SET post_lifetime_hours = @hours
              WHERE id = @id
            '''),
            parameters: {'id': _requestDraft, 'hours': 24},
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23514'),
          ),
        );
      },
    );

    test('rejects an invite tied to a Post that is still a draft', () async {
      await expectLater(
        invitations.create(
          userId: _author,
          addresseeName: 'Garden visitor',
          beaconId: _beacon,
        ),
        throwsA(isA<PostNotOpenException>()),
      );
    });

    test(
      'lets the author create an invite after publishing the Post to nobody, '
      'and stores the Post id on the invitation',
      () async {
        await updatePostDraft(
          forwardPolicy: BeaconForwardPolicyValue.open.value,
        );
        await posts.publish(
          authorId: _author,
          beaconId: _beacon,
          body: _publishBody,
          mentionUserIds: const [],
          mentionOffsets: const [],
          mentionLengths: const [],
          recipientIds: const [],
          notes: const {},
          forwardPolicy: BeaconForwardPolicyValue.open,
        );

        final invitation = await invitations.create(
          userId: _author,
          addresseeName: 'Garden visitor',
          beaconId: _beacon,
        );
        expect(invitation.beaconId, _beacon);
      },
    );
  });
}
