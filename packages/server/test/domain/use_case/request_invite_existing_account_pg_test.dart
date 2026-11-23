@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _author = 'U1a95ea4e0001';
const _relay = 'U1a95ea4e0002';
const _issuer = 'U1a95ea4e0003';
const _acceptingAccount = 'U1a95ea4e0004';
const _liveAccount = 'U1a95ea4e0005';
const _request = 'B1a95ea4e0001';
const _ancestor = 'F1a95ea4e0001';
const _parent = 'F1a95ea4e0002';
const _origin = 'http://127.0.0.1:2080';

enum _AcceptancePath {
  byCode('Accepting a Request invite by code'),
  byId('Accepting a Request invite by invitation ID');

  const _AcceptancePath(this.label);

  final String label;

  Future<Object?> accept(
    InvitationCase invitations,
    String invite,
    String user,
  ) => switch (this) {
    byCode => invitations.acceptAsExisting(code: invite, userId: user),
    byId => invitations.accept(invitationId: invite, userId: user),
  };
}

enum _LapseGate {
  closed('the Request closes'),
  expired('the Request expires'),
  unreadable('the issuer loses access to the Request'),
  cannotForward('the issuer loses the right to forward the Request'),
  cancelledAncestor('an ancestor of the parent forward is cancelled');

  const _LapseGate(this.description);

  final String description;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_REQUEST_INVITE_EXISTING_ACCOUNT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_request_invite_existing',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late Connection writer;
  late InvitationCase invitations;

  setUpAll(() async {
    final warnSetting = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = warnSetting;
    });
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() async {
      try {
        await getIt.reset();
      } finally {
        await tearDownDisposablePgWriter(session: session);
      }
    });
    writer = session.writer;
    final db = target.databaseEnv;
    await configureDependencies(
      Env(
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
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
        isNeedInvite: true,
        genealogyNodeKeySecret: 'test-genealogy-secret',
      ),
    );
    await getIt.allReady(ignorePendingAsyncCreation: true);
    invitations = getIt<InvitationCase>();
  });

  Future<Result> query(String sql, Map<String, Object?> args) =>
      writer.execute(Sql.named(sql), parameters: args);

  setUp(() async {
    await writer.execute('''
TRUNCATE public.attention_occurrence, public.invitation,
  public.beacon, public."user" CASCADE
''');
    const people = {
      _author: 'Request author',
      _relay: 'First recipient',
      _issuer: 'Invite issuer',
      _acceptingAccount: 'Existing member',
      _liveAccount: 'Another member',
    };
    for (final (slot, person) in people.entries.indexed) {
      await query(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @key)
''',
        {
          'id': person.key,
          'name': person.value,
          'key': pgTestPublicKey('requestInviteExistingAccount', slot + 1),
        },
      );
    }
  });

  Future<void> publishRequest({required bool withParentChain}) async {
    await query(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES (@request, @author, 'Community garden', 'Help planting seedlings',
  @status, @kind, @policy, @discoverable, now())
''',
      {
        'request': _request,
        'author': _author,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
        'policy': BeaconForwardPolicyValue.open.value,
        'discoverable': !withParentChain,
      },
    );
    if (withParentChain) {
      await query(
        '''
INSERT INTO public.beacon_forward_edge
  (id, beacon_id, sender_id, recipient_id, parent_edge_id)
VALUES (@ancestor, @request, @author, @relay, NULL),
       (@parent, @request, @relay, @issuer, @ancestor)
''',
        {
          'ancestor': _ancestor,
          'parent': _parent,
          'request': _request,
          'author': _author,
          'relay': _relay,
          'issuer': _issuer,
        },
      );
    } else {
      await query(
        '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@author, @issuer, 1), (@issuer, @author, 1)
''',
        {'author': _author, 'issuer': _issuer},
      );
    }
  }

  Future<String> issueInvite(String addressee) async {
    final invite = await invitations.create(
      userId: _issuer,
      addresseeName: addressee,
      beaconId: _request,
    );
    return invite.id;
  }

  Future<void> changeStatus(BeaconStatus status) async {
    await query(
      'UPDATE public.beacon SET status = @status WHERE id = @request',
      {'status': status.smallintValue, 'request': _request},
    );
  }

  Future<void> lapseRequest(_LapseGate gate) async {
    switch (gate) {
      case _LapseGate.closed:
        await changeStatus(BeaconStatus.closed);
      case _LapseGate.expired:
        await query(
          'UPDATE public.beacon SET expires_at = now() WHERE id = @request',
          {'request': _request},
        );
        expect(
          await query(
            'SELECT status, expires_at <= now() FROM public.beacon WHERE id = @request',
            {'request': _request},
          ),
          [
            [BeaconStatus.open.smallintValue, true],
          ],
        );
      case _LapseGate.unreadable:
        await query(
          'UPDATE public.beacon SET is_discoverable = false WHERE id = @request',
          {'request': _request},
        );
      case _LapseGate.cannotForward:
        await changeStatus(BeaconStatus.reviewOpen);
        await expectLater(
          issueInvite('Another invitee'),
          throwsA(isA<UnauthorizedException>()),
        );
      case _LapseGate.cancelledAncestor:
        await query(
          'UPDATE public.beacon_forward_edge SET cancelled_at = now() WHERE id = @ancestor',
          {'ancestor': _ancestor},
        );
        expect(
          await query(
            '''
SELECT parent_edge_id, cancelled_at IS NULL
FROM public.beacon_forward_edge WHERE id = @parent
''',
            {'parent': _parent},
          ),
          [
            [_ancestor, true],
          ],
          reason: 'The invite still points to a live parent forward',
        );
    }
    expect(
      await query(
        'SELECT public.beacon_can_read_content(@request, @issuer)',
        {'request': _request, 'issuer': _issuer},
      ),
      [
        [gate != _LapseGate.unreadable],
      ],
      reason: 'Only the unreadable Request should fail the content gate',
    );
  }

  Future<Result> readClaim(String invite) => query(
    'SELECT invited_id, accepted_at FROM public.invitation WHERE id = @invite',
    {'invite': invite},
  );

  Future<void> expectConsumedInvite(
    String invite, {
    required String account,
    List<Object?>? liveForward,
  }) async {
    final claim = await readClaim(invite);
    final votes = await query(
      '''
SELECT subject, object FROM public.vote_user
WHERE (subject = @issuer AND object = @account)
   OR (subject = @account AND object = @issuer)
''',
      {'issuer': _issuer, 'account': account},
    );
    final forwards = await query(
      '''
SELECT sender_id, parent_edge_id, cancelled_at IS NULL
FROM public.beacon_forward_edge
WHERE beacon_id = @request AND recipient_id = @account
''',
      {'request': _request, 'account': account},
    );

    expect(
      {'claim': claim, 'votes': votes, 'forwards': forwards},
      {
        'claim': [
          [account, isNotNull],
        ],
        'votes': isEmpty,
        'forwards': [?liveForward],
      },
    );
  }

  group('Invites to Requests whose author account was deleted', () {
    Future<String> issueInviteBeforeAuthorDeletion(BeaconStatus status) async {
      await publishRequest(withParentChain: true);
      final invite = await issueInvite('Existing member');
      if (status == BeaconStatus.deleted) {
        await changeStatus(status);
      } else {
        // The migrated schema requires open Requests to have an owner.
        // Lift that check only in this disposable database to exercise the
        // application's handling of an open row after account deletion.
        await writer.execute(
          'ALTER TABLE public.beacon DROP CONSTRAINT beacon_owner_or_deleted_ck',
        );
        addTearDown(() async {
          await changeStatus(BeaconStatus.deleted);
          await writer.execute('''
ALTER TABLE public.beacon ADD CONSTRAINT beacon_owner_or_deleted_ck
CHECK (user_id IS NOT NULL OR status = ${BeaconStatus.deleted.smallintValue})
''');
        });
      }
      await query('DELETE FROM public."user" WHERE id = @author', {
        'author': _author,
      });
      expect(
        await query(
          '''
SELECT beacon.user_id, beacon.status, beacon.kind, invitation.user_id,
  invitation.invited_id, invitation.accepted_at
FROM public.invitation AS invitation
JOIN public.beacon AS beacon ON beacon.id = invitation.beacon_id
WHERE invitation.id = @invite AND beacon.id = @request
''',
          {'invite': invite, 'request': _request},
        ),
        [
          [
            null,
            status.smallintValue,
            BeaconKind.request.value,
            _issuer,
            null,
            null,
          ],
        ],
        reason:
            'The unused invite still points to the Request without an author',
      );
      return invite;
    }

    for (final (status, label) in [
      (BeaconStatus.deleted, 'a deleted Request'),
      (BeaconStatus.open, 'an open Request'),
    ]) {
      test('offers account acceptance and shows $label as lapsed', () async {
        final invite = await issueInviteBeforeAuthorDeletion(status);

        final preview = (await invitations.preview(
          code: invite,
          callerUserId: _acceptingAccount,
        )).toJson();
        expect(preview, containsPair('codeStatus', 'available'));
        expect(preview, containsPair('callerStatus', 'existing-user'));
        expect(preview, containsPair('suggestedAction', 'accept-as-existing'));
        expect(
          preview,
          containsPair(
            'beacon',
            allOf(
              containsPair('id', _request),
              containsPair('kind', 'request'),
              containsPair('lapsed', true),
            ),
          ),
        );
      });

      for (final path in _AcceptancePath.values) {
        group(path.label, () {
          test(
            'consumes the invite to $label without granting access or creating a connection',
            () async {
              final invite = await issueInviteBeforeAuthorDeletion(status);

              expect(
                await path.accept(invitations, invite, _acceptingAccount),
                InviteAcceptance.requestLapsed,
              );
              await expectConsumedInvite(invite, account: _acceptingAccount);
            },
          );
        });
      }
    }

    test('shows a deleted Request as lapsed before sign-in', () async {
      final invite = await issueInviteBeforeAuthorDeletion(
        BeaconStatus.deleted,
      );

      final preview = (await invitations.preview(code: invite)).toJson();
      expect(preview, containsPair('codeStatus', 'available'));
      expect(preview, containsPair('callerStatus', 'anonymous'));
      expect(preview, containsPair('beacon', containsPair('lapsed', true)));
    });

    test(
      'rejects reuse of a lapsed invite code and preserves the original claim',
      () async {
        final invite = await issueInviteBeforeAuthorDeletion(
          BeaconStatus.deleted,
        );

        expect(
          await invitations.acceptAsExisting(
            code: invite,
            userId: _acceptingAccount,
          ),
          InviteAcceptance.requestLapsed,
        );
        await expectConsumedInvite(invite, account: _acceptingAccount);
        final firstClaim = await readClaim(invite);

        await expectLater(
          invitations.acceptAsExisting(code: invite, userId: _liveAccount),
          throwsA(isA<IdNotFoundException>()),
        );
        expect(await readClaim(invite), firstClaim);
      },
    );
  });

  group('Invite preview before joining', () {
    for (final gate in _LapseGate.values) {
      test(
        'keeps the Request title and signup when ${gate.description}',
        () async {
          final withParentChain = gate != _LapseGate.unreadable;
          await publishRequest(withParentChain: withParentChain);
          final invite = await issueInvite('New member');
          if (withParentChain) {
            expect(
              await query(
                'SELECT parent_forward_edge_id FROM public.invitation WHERE id = @id',
                {'id': invite},
              ),
              [
                [_parent],
              ],
            );
          }
          await lapseRequest(gate);

          final preview = (await invitations.preview(code: invite)).toJson();
          expect(preview, containsPair('callerStatus', 'anonymous'));
          expect(preview, containsPair('codeStatus', 'available'));
          expect(preview, containsPair('suggestedAction', 'accept-as-new'));
          expect(
            preview['inviter'],
            containsPair('displayName', 'Invite issuer'),
          );
          expect(
            preview,
            containsPair(
              'beacon',
              allOf(
                containsPair('kind', 'request'),
                containsPair('title', 'Community garden'),
                containsPair('lapsed', true),
              ),
            ),
          );
        },
      );
    }

    test(
      'offers an existing account acceptance after the Request closes',
      () async {
        await publishRequest(withParentChain: true);
        final invite = await issueInvite('Existing member');
        await lapseRequest(_LapseGate.closed);

        final preview = (await invitations.preview(
          code: invite,
          callerUserId: _acceptingAccount,
        )).toJson();
        expect(preview, containsPair('callerStatus', 'existing-user'));
        expect(preview, containsPair('codeStatus', 'available'));
        expect(preview, containsPair('suggestedAction', 'accept-as-existing'));
        expect(
          preview,
          containsPair(
            'beacon',
            allOf(
              containsPair('title', 'Community garden'),
              containsPair('lapsed', true),
            ),
          ),
        );
      },
    );

    test(
      'includes details for an open Request and omits them for a plain invite',
      () async {
        final plain = await invitations.create(
          userId: _issuer,
          addresseeName: 'New member',
        );
        final plainPreview = (await invitations.preview(
          code: plain.id,
        )).toJson();
        expect(plainPreview, containsPair('codeStatus', 'available'));
        expect(plainPreview, isNot(contains('beacon')));

        await publishRequest(withParentChain: true);
        final invite = await issueInvite('Another member');
        final preview = (await invitations.preview(code: invite)).toJson();
        expect(preview, containsPair('codeStatus', 'available'));
        expect(preview['beacon'], {
          'id': _request,
          'kind': 'request',
          'title': 'Community garden',
          'snippet': 'Help planting seedlings',
          'description': 'Help planting seedlings',
          'lapsed': false,
        });
      },
    );

    test('never marks a Post as lapsed, even after it closes', () async {
      const post = 'B1a95ea4e0002';
      const root = 'M1a95ea4e0001';
      await query(
        '''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES (@post, @author, '', '', @status, @kind, @policy, false, now())
''',
        {
          'post': post,
          'author': _author,
          'status': BeaconStatus.open.smallintValue,
          'kind': BeaconKind.post.value,
          'policy': BeaconForwardPolicyValue.open.value,
        },
      );
      await query(
        '''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@root, @post, @author, 'Updates from the garden')
''',
        {'root': root, 'post': post, 'author': _author},
      );
      await query(
        'UPDATE public.beacon SET post_root_message_id = @root WHERE id = @post',
        {'root': root, 'post': post},
      );
      final invite = await invitations.create(
        userId: _author,
        addresseeName: 'New member',
        beaconId: post,
      );
      final open = (await invitations.preview(code: invite.id)).toJson();
      expect(open, containsPair('codeStatus', 'available'));
      expect(open['beacon'], containsPair('kind', 'post'));

      await query(
        'UPDATE public.beacon SET status = @status WHERE id = @post',
        {'status': BeaconStatus.closed.smallintValue, 'post': post},
      );
      final closed = (await invitations.preview(code: invite.id)).toJson();
      expect(closed, containsPair('codeStatus', 'available'));
      expect(closed, isNot(contains('beacon')));
      expect(open['beacon'], containsPair('lapsed', false));
    });
  });

  for (final path in _AcceptancePath.values) {
    group(path.label, () {
      for (final gate in _LapseGate.values) {
        test(
          'consumes the invite without admission when ${gate.description}',
          () async {
            final parent = gate == _LapseGate.unreadable ? null : _parent;
            await publishRequest(withParentChain: parent != null);
            final invite = await issueInvite('Existing member');
            expect(
              await query(
                'SELECT parent_forward_edge_id FROM public.invitation WHERE id = @id',
                {'id': invite},
              ),
              [
                [parent],
              ],
            );

            final liveInvite = await issueInvite('Another member');
            final liveOutcome = await path.accept(
              invitations,
              liveInvite,
              _liveAccount,
            );
            expect(liveOutcome, isNot(anyOf(isNull, isFalse)));
            await expectConsumedInvite(
              liveInvite,
              account: _liveAccount,
              liveForward: [_issuer, parent, true],
            );

            await lapseRequest(gate);
            final lapsedOutcome = await path.accept(
              invitations,
              invite,
              _acceptingAccount,
            );
            await expectConsumedInvite(invite, account: _acceptingAccount);
            // Compare observable results without choosing their representation.
            expect(
              lapsedOutcome,
              isNot(anyOf(isNull, isFalse, equals(liveOutcome))),
              reason:
                  'A consumed lapsed invite has a result distinct from admission',
            );
          },
        );
      }
    });
  }

  test('a consumed lapsed invite code cannot be used again', () async {
    await publishRequest(withParentChain: true);
    final invite = await issueInvite('Existing member');
    await lapseRequest(_LapseGate.cancelledAncestor);

    await invitations.acceptAsExisting(code: invite, userId: _acceptingAccount);
    final firstClaim = await readClaim(invite);
    await expectLater(
      invitations.acceptAsExisting(code: invite, userId: _acceptingAccount),
      throwsA(isA<IdNotFoundException>()),
    );

    expect(await readClaim(invite), firstClaim);
    await expectConsumedInvite(invite, account: _acceptingAccount);
  });

  group('Closing a Request after an invite is issued', () {
    late String invite;
    late Handler api;
    late Map<String, String> headers;

    setUp(() async {
      await publishRequest(withParentChain: true);
      invite = await issueInvite('Existing member');
      await lapseRequest(_LapseGate.closed);
      api = (await getIt.getAsync<RootRouter>()).routeHandler();
      final token = getIt<AuthCase>()
          .issueAccessToken(_acceptingAccount)
          .rawToken;
      headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };
    });

    test('accept-by-code responds with HTTP 200 and a JSON object', () async {
      final response = await api(
        Request(
          'POST',
          Uri.parse('$_origin/api/v2/invite/$invite/accept-as-existing'),
          headers: headers,
        ),
      );
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      expect(jsonDecode(body), isA<Map<String, Object?>>());
      await expectConsumedInvite(invite, account: _acceptingAccount);
    });

    test('invitationAccept resolves without a GraphQL error', () async {
      final response = await api(
        Request(
          'POST',
          Uri.parse('$_origin/api/v2/graphql'),
          headers: headers,
          body: jsonEncode({
            'query': r'''
mutation AcceptRequestInvite($id: String!) {
  invitationAccept(id: $id)
}
''',
            'variables': {'id': invite},
          }),
        ),
      );
      final body = await response.readAsString();
      expect(response.statusCode, 200, reason: body);
      final payload = jsonDecode(body) as Map<String, Object?>;
      expect(payload['errors'], anyOf(isNull, isEmpty), reason: body);
      expect(payload['data'], containsPair('invitationAccept', isNotNull));
      await expectConsumedInvite(invite, account: _acceptingAccount);
    });
  });
}
