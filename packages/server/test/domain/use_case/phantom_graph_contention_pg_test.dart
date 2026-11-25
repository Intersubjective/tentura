@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/people_tag_consts.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';
import 'package:tentura_server/domain/trust/trust_evidence_kind.dart';
import 'package:tentura_server/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura_server/domain/use_case/contact_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/people_tags_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/use_case/user_erasure_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/session_database_di_harness.dart';

const _owner = 'U781r00000001';
const _joiner = 'U781r00000002';
const _other = 'U781r00000003';
const _request = 'B781r00000001';
const _savedPin = ConstellationAnchorPosition(
  xUnits: 12.25,
  yUnits: -6.5,
  coordinateSpaceVersion: 1,
);
const _movedPin = ConstellationAnchorPosition(
  xUnits: 9.5,
  yUnits: 18.75,
  coordinateSpaceVersion: 1,
);
const _pair = {'owner': _owner, 'user': _joiner};
const _signupEmail = 'concurrent-signup@example.test';
const _gateKey = 78119001;
const _completionLimit = Duration(seconds: 6);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_GRAPH_CONTENTION_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_graph_race',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Concurrent changes to private map entries', () {
    late _Database fixture;

    setUpAll(() async {
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
      });
      final session = await setUpDisposablePgWriter(target: target);
      addTearDown(() => tearDownDisposablePgWriter(session: session));
      await enforceOwnerScope(session);
      addTearDown(() async {
        getIt.skipDoubleRegistration = false;
        await getIt.reset();
      });
      final db = target.databaseEnv;
      const origin = 'http://127.0.0.1:2080';
      final env = Env(
        environment: db.environment,
        serverUri: Uri.parse(origin),
        publicOrigin: origin,
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
      );
      await configureSessionDatabaseTestGraph(env);
      fixture = _Database(session.writer, env);
    });

    setUp(() async {
      await fixture.sql(
        'TRUNCATE public."user", public.attention_occurrence CASCADE',
      );
      for (final (index, id) in [_owner, _joiner, _other].indexed) {
        await fixture.sql(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @name, @key)',
          {
            'id': id,
            'name': 'Account ${index + 1}',
            'key': pgTestPublicKey('graph-contention', index + 1),
          },
        );
      }
    });

    group('Merging and moving private pins', () {
      test(
        'a link moves the saved pin and advances both target revisions while a batch moves another pin',
        () async {
          final entry = await fixture.createInvite(position: _savedPin);
          final otherPin = await fixture.createPin();
          expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          final beforeEntry = await fixture.pinRevision('PHANTOM', entry.id);
          final beforeAccount = await fixture.pinRevision('PERSON', _joiner);

          final (mergeError, batchError) = await fixture.race(
            pauseOn: 'AFTER INSERT ON public.phantom_merge',
            first: fixture.runWorker,
            second: () => fixture.movePin(otherPin),
            requireSecondWait: true,
          );

          expect((mergeError, batchError), (null, null));
          await fixture.expectDone(entry);
          expect(await fixture.pin('PHANTOM', entry.id), isEmpty);
          expect(await fixture.pin('PHANTOM', otherPin), [
            [9.5, 18.75],
          ]);
          expect(await fixture.pin('PERSON', _joiner), [
            [12.25, -6.5],
          ]);
          expect(
            await fixture.pinRevision('PHANTOM', entry.id),
            greaterThan(beforeEntry),
          );
          expect(
            await fixture.pinRevision('PERSON', _joiner),
            greaterThan(beforeAccount),
          );
        },
      );

      test(
        'accepting an invite queues its link while the owner moves another pin',
        () async {
          final entry = await fixture.createInvite(position: _savedPin);
          final otherPin = await fixture.createPin();

          final (batchError, acceptError) = await fixture.race(
            pauseOn: 'AFTER UPDATE ON public.constellation_anchor',
            when: "NEW.target_id = '$otherPin'",
            first: () => fixture.movePin(otherPin),
            second: () async {
              expect(
                await fixture.accept(entry.code),
                InviteAcceptance.accepted,
              );
              await fixture.expectQueuedFor(entry, _joiner);
            },
            requireSecondCompletion: true,
          );

          expect((batchError, acceptError), (null, null));
          await fixture.runWorker();
          await fixture.expectDone(entry);
          expect(await fixture.pin('PHANTOM', otherPin), [
            [9.5, 18.75],
          ]);
          expect(await fixture.pin('PERSON', _joiner), [
            [12.25, -6.5],
          ]);
        },
      );
    });

    test('a link uses the name committed by a concurrent rename', () async {
      final entry = await fixture.createInvite();
      expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
      const updated = 'Neighbour from the garden';

      final (renameError, mergeError) = await fixture.race(
        pauseOn: 'AFTER UPDATE OF display_name ON public.phantom',
        when: "NEW.id = '${entry.id}'",
        first: () async {
          expect(
            await getIt<PhantomCase>().update(
              ownerId: _owner,
              id: entry.id,
              name: updated,
            ),
            isTrue,
          );
        },
        second: fixture.runWorker,
        requireSecondWait: true,
      );

      expect((renameError, mergeError), (null, null));
      await fixture.expectDone(entry);
      expect(await fixture.contacts(), [
        [_owner, _joiner, updated],
      ]);
    });

    test(
      'erasing an account during a link leaves no merge, pin, tag, or held job for it',
      () async {
        final entry = await fixture.createInvite(position: _savedPin);
        final tags = getIt<PeopleTagsCase>();
        final tag = await tags.create(
          ownerId: _owner,
          name: 'Neighbours',
          clientOpId: 'tag',
        );
        await tags.applyMembers(
          ownerId: _owner,
          clientOpId: 'assign-neighbours',
          ops: [
            {
              'tagId': tag.id,
              'personId': entry.id,
              'op': 'add',
              'source': kPersonTagSourceManual,
            },
          ],
        );
        expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
        await fixture.expectQueuedFor(entry, _joiner);

        final (eraseError, workerError) = await fixture.race(
          pauseOn: 'BEFORE DELETE ON public."user"',
          forEach: 'STATEMENT',
          first: () async {
            expect(
              await getIt<AccountErasureCase>().deleteById(id: _joiner),
              isTrue,
            );
          },
          second: fixture.runWorker,
        );

        expect((workerError, eraseError), (null, null));
        // Include the target ID a pin can retain after its person FK clears.
        final rows = await fixture.sql(
          '''
SELECT
  (SELECT count(*) FROM public."user" WHERE id = @user) AS accounts,
  (SELECT count(*) FROM public.phantom_merge WHERE user_id = @user) AS merges,
  (SELECT count(*) FROM public.constellation_anchor
     WHERE person_id = @user OR (target_kind = 'PERSON' AND target_id = @user)) AS pins,
  (SELECT count(*) FROM public.person_tag_member WHERE person_id = @user) AS tags,
  (SELECT count(*) FROM public.phantom_merge_job WHERE invitation_id = @code
     AND (state = 'failed' OR (state = 'queued' AND lease_owner IS NOT NULL))) AS jobs
''',
          {'user': _joiner, 'code': entry.code},
        );
        expect(rows.single.toColumnMap(), {
          'accounts': 0,
          'merges': 0,
          'pins': 0,
          'tags': 0,
          'jobs': 0,
        });
      },
    );

    test(
      'a block racing invite acceptance cleans up the pair before the queued link runs',
      () async {
        final entry = await fixture.createInvite();
        await fixture.seedForward();
        await getIt<ContactCase>().set(
          viewerId: _owner,
          subjectId: _joiner,
          contactName: 'Saved neighbour',
        );

        final (acceptError, blockError) = await fixture.race(
          pauseOn: 'AFTER UPDATE OF invited_id ON public.invitation',
          when: "NEW.id = '${entry.code}'",
          first: () async {
            expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          },
          second: fixture.block,
          requireSecondWait: true,
        );

        expect((acceptError, blockError), (null, null));
        await fixture.expectQueuedFor(entry, _joiner);
        expect(await fixture.contacts(), isEmpty);
        expect(await fixture.activeForwards(), isEmpty);
        expect(
          await fixture.sql('''
SELECT blocker_id, blocked_id FROM public.user_block
WHERE blocker_id = @owner AND blocked_id = @user
''', _pair),
          [
            [_owner, _joiner],
          ],
        );
        await fixture.runWorker();
        await fixture.expectSkippedForBlock(entry);
      },
    );

    test(
      'an expired worker waiting on the private map cannot duplicate the replacement worker’s link',
      () async {
        final entry = await fixture.createInvite();
        expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
        final now = DateTime.timestamp();
        final graph = getIt<OwnerGraphTransactionPort>();
        Future<void>? firstWorker;
        Future<void>? secondWorker;
        try {
          await whileOwnerGraphScopeHeld(graph, _owner, () async {
            firstWorker = fixture.runWorker(
              leaseOwner: 'original-worker',
              now: now,
            )..ignore();
            expect(
              await waitsForOwnerGraphScope(
                fixture.writer,
                _owner,
                firstWorker!,
              ),
              isTrue,
            );
            expect(await fixture.lease(entry), [
              ['queued', 'original-worker', 1],
            ]);
            secondWorker = fixture.runWorker(
              leaseOwner: 'replacement-worker',
              now: now.add(const Duration(minutes: 3)),
            )..ignore();
            await fixture.waitForLease(
              entry,
              'replacement-worker',
              secondWorker!,
            );
            expect(await fixture.lease(entry), [
              ['queued', 'replacement-worker', 2],
            ]);
            expect(
              await fixture.sql(
                'SELECT id FROM public.phantom_merge WHERE phantom_id = @id',
                {'id': entry.id},
              ),
              isEmpty,
            );
          });
        } finally {
          await Future.wait([
            ?firstWorker,
            ?secondWorker,
          ]).timeout(_completionLimit);
        }

        await fixture.expectDone(entry);
        expect(await fixture.lease(entry), [
          ['done', 'replacement-worker', 2],
        ]);
      },
    );

    group('Retrying an invite under trust contention', () {
      test(
        'an invite retries its claim while two independent votes contend for its voters',
        () async {
          final entry = await fixture.createInvite();
          await fixture.countAcceptAttempts(entry.code, failFirstCommit: true);

          await fixture.raceVotesAgainstAccept(entry);
          expect(await fixture.acceptAttempts(), 2);
          await fixture.expectQueuedFor(entry, _joiner);
          await fixture.runWorker();
          await fixture.expectDone(entry);
          expect(
            await fixture.allVotes(),
            unorderedEquals([
              [_owner, _other, 1],
              [_joiner, _other, 1],
              [_owner, _joiner, 1],
              [_joiner, _owner, 1],
            ]),
          );
          expect(
            await fixture.activeTrust(),
            unorderedEquals([
              [_owner, _other],
              [_joiner, _other],
              [_owner, _joiner],
              [_joiner, _owner],
            ]),
          );
        },
      );

      test(
        'a Request invite retries its forward and engagement while the same pair unlinks',
        () async {
          final entry = await fixture.createInvite();
          expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          await fixture.runWorker();
          await fixture.expectDone(entry);

          await fixture.seedRequest();
          final inbound =
              (await fixture.sql(
                    '''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, contact_deadline_at)
VALUES (@request, @user, @owner, now() + interval '1 hour')
RETURNING id
''',
                    {..._pair, 'request': _request},
                  )).single.single!
                  as String;
          final invite = await getIt<InvitationCase>().create(
            userId: _owner,
            addresseeName: '',
            beaconId: _request,
          );
          await fixture.countAcceptAttempts(invite.id, failFirstCommit: true);

          final (acceptError, unlinkError) = await fixture.race(
            pauseOn: 'AFTER INSERT ON public.trust_evidence',
            when: "NEW.source_key = 'contact:$inbound:engaged'",
            first: () async {
              expect(
                await fixture.accept(invite.id),
                InviteAcceptance.accepted,
              );
            },
            second: () async {
              expect(
                await getIt<PhantomMergeCase>().unmerge(
                  ownerId: _owner,
                  phantomId: entry.id,
                ),
                isTrue,
              );
            },
          );

          expect((acceptError, unlinkError), (null, null));
          expect(await fixture.acceptAttempts(), 2);
          expect(
            await fixture.sql(
              'SELECT invited_id FROM public.invitation WHERE id = @id',
              {'id': invite.id},
            ),
            [
              [_joiner],
            ],
          );
          expect(
            await fixture.sql(
              '''
SELECT sender_id, recipient_id FROM public.beacon_forward_edge
WHERE beacon_id = @request AND sender_id = @owner AND cancelled_at IS NULL
''',
              {'owner': _owner, 'request': _request},
            ),
            [
              [_owner, _joiner],
            ],
          );
          expect(
            await fixture.sql(
              '''
SELECT subject_user_id, object_user_id, count FROM public.trust_evidence
WHERE source_key = @source AND retracted_at IS NULL
''',
              {'source': 'contact:$inbound:engaged'},
            ),
            [
              [_owner, _joiner, 1.0],
            ],
          );
          expect(
            await fixture.sql(
              'SELECT contact_outcome FROM public.beacon_forward_edge WHERE id = @id',
              {'id': inbound},
            ),
            [
              [1],
            ],
          );
          expect(await fixture.contacts(), isEmpty);
          await fixture.expectUndone(entry);
          expect(await fixture.allVotes(), [
            [_joiner, _owner, 1],
          ]);
          expect(
            await fixture.activeTrust(),
            unorderedEquals([
              [_joiner, _owner],
              [_owner, _joiner],
            ]),
          );
        },
      );

      test(
        'an invite retries after a deadlock with a trust ledger write for the same pair',
        () async {
          final entry = await fixture.createInvite();
          await fixture.countAcceptAttempts(entry.code);
          const evidence = LedgerEvidence(
            subjectId: _owner,
            objectId: _joiner,
            kind: TrustEvidenceKind.vouch,
            count: 1,
            sourceKey: 'concurrent-vouch',
          );

          await fixture.deferDeadlockDetection(
            on: 'AFTER INSERT ON public.trust_evidence',
            when: "NEW.source_key = '${evidence.sourceKey}'",
          );
          // The vote statement takes the generation row. While it is paused,
          // the ledger takes the pair lock and reaches its generation wait.
          // When accept resumes, it starts waiting with the cycle already closed.
          final (acceptError, ledgerError) = await fixture.race(
            pauseOn: 'AFTER INSERT ON public.vote_user',
            forEach: 'STATEMENT',
            first: () async {
              expect(
                await fixture.accept(entry.code),
                InviteAcceptance.accepted,
              );
            },
            second: () => getIt<MutatingUnitOfWorkPort>().run(
              actorUserId: _owner,
              action: () => getIt<TrustLedgerPort>().record([evidence]),
            ),
            requireSecondWait: true,
          );

          expect((ledgerError, acceptError), (null, null));
          expect(await fixture.acceptAttempts(), 2);
          expect(
            await fixture.sql(
              '''
SELECT subject_user_id, object_user_id, count FROM public.trust_evidence
WHERE source_key = @source AND retracted_at IS NULL
''',
              {'source': evidence.sourceKey},
            ),
            [
              [_owner, _joiner, 1.0],
            ],
          );
          expect(
            await fixture.allVotes(),
            unorderedEquals([
              [_owner, _joiner, 1],
              [_joiner, _owner, 1],
            ]),
          );
          expect(
            await fixture.activeTrust(),
            unorderedEquals([
              [_owner, _joiner],
              [_joiner, _owner],
            ]),
          );
          await fixture.expectQueuedFor(entry, _joiner);
          await fixture.runWorker();
          await fixture.expectDone(entry);
        },
      );
    });

    test(
      'a tag edit waiting for a link keeps the tag on the joined account and in Undo',
      () async {
        final entry = await fixture.createInvite();
        expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
        final tags = getIt<PeopleTagsCase>();
        final tag = await tags.create(
          ownerId: _owner,
          name: 'Neighbours',
          clientOpId: 'create-neighbours',
        );

        final (mergeError, tagError) = await fixture.race(
          pauseOn: 'AFTER INSERT ON public.phantom_merge',
          first: fixture.runWorker,
          second: () => tags.applyMembers(
            ownerId: _owner,
            clientOpId: 'tag-private-entry',
            ops: [
              {
                'tagId': tag.id,
                'personId': entry.id,
                'op': 'add',
                'source': kPersonTagSourceManual,
              },
            ],
          ),
        );

        expect(mergeError, isNull);
        await fixture.expectDone(entry);
        final membership = await fixture.sql(
          'SELECT membership_id::text FROM public.person_tag_member '
          'WHERE owner_id = @owner AND person_id = @user AND tag_id = @tag',
          {'owner': _owner, 'user': _joiner, 'tag': tag.id},
        );
        final undo =
            jsonDecode(
                  (await fixture.sql(
                        'SELECT undo::text FROM public.phantom_merge WHERE phantom_id = @id',
                        {'id': entry.id},
                      )).single.single!
                      as String,
                )
                as Map<String, dynamic>;
        expect(
          {
            'caller error': tagError,
            'joined account membership': membership.singleOrNull?.single,
            'original tags': (undo['phantomMemberships'] as List<dynamic>)
                .map((row) => (row as Map<String, dynamic>)['tag_id'])
                .toList(),
            'recorded memberships': undo['insertedMembershipIds'],
          },
          {
            'caller error': isNull,
            'joined account membership': isA<String>(),
            'original tags': [tag.id],
            'recorded memberships': [membership.singleOrNull?.single],
          },
        );
      },
    );

    for (final remove in [true, false]) {
      test(
        remove
            ? 'removing an entry while its link is queued reports that the person is joining and preserves the link'
            : 'copying the invite while its link is queued reports that the person is joining without changing the invite',
        () async {
          final entry = await fixture.createInvite();
          expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          final before = await fixture.invitations(entry.id);
          expect(before, hasLength(1));
          expect(before.single['invited_id'], _joiner);
          expect(
            (await fixture.sql(
              'SELECT state FROM public.phantom_merge_job WHERE invitation_id = @code',
              {'code': entry.code},
            )).single.single,
            'queued',
          );

          final phantoms = getIt<PhantomCase>();
          final (workerError, ownerError) = await fixture.race(
            pauseOn: 'AFTER INSERT ON public.phantom_merge',
            first: fixture.runWorker,
            second: remove
                ? () => phantoms.delete(ownerId: _owner, id: entry.id)
                : () => phantoms.saveInvite(
                    ownerId: _owner,
                    id: entry.id,
                    rotate: false,
                  ),
          );

          expect(workerError, isNull);
          expect(
            {
              'caller result': ownerError,
              'invitation records': await fixture.invitations(entry.id),
              'link records': await fixture.sql(
                'SELECT user_id FROM public.phantom_merge WHERE phantom_id = @id',
                {'id': entry.id},
              ),
            },
            {
              'caller result': isA<PhantomJoiningException>(),
              'invitation records': before,
              'link records': [
                [_joiner],
              ],
            },
          );
          await fixture.expectDone(entry);
        },
      );
    }

    test(
      'signup racing a winning existing-account claim reports an already-used invitation',
      () async {
        final entry = await fixture.createInvite();
        final (acceptError, signupError) = await fixture.race(
          pauseOn: 'AFTER UPDATE OF invited_id ON public.invitation',
          when: "NEW.invited_id = '$_joiner'",
          first: () async {
            expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          },
          second: () => fixture.signUp(entry.code),
        );

        expect(acceptError, isNull);
        await fixture.expectQueuedFor(entry, _joiner);
        await fixture.runWorker();
        await fixture.expectDone(entry);
        expect(
          await fixture.sql(
            'SELECT id FROM public."user" WHERE display_name = @name',
            {'name': 'New neighbour'},
          ),
          isEmpty,
          reason: 'The losing signup must roll back its account.',
        );
        expect(
          signupError,
          isA<InvitationWrongException>().having(
            (error) => error.reason,
            'invitation result',
            InvitationWrongReason.used,
          ),
        );
      },
    );

    test(
      'an existing account racing a winning signup gets an already-used invitation',
      () async {
        final entry = await fixture.createInvite();
        String? signupAccount;
        InviteAcceptance? existingResult;

        final (signupError, acceptError) = await fixture.race(
          pauseOn: 'AFTER UPDATE OF invited_id ON public.invitation',
          when: "NEW.invited_id <> '$_joiner'",
          first: () async {
            signupAccount = await fixture.signUp(entry.code);
          },
          second: () async {
            existingResult = await fixture.accept(entry.code);
          },
        );

        expect(signupError, isNull);
        final winner = signupAccount!;
        await fixture.expectQueuedFor(entry, winner);
        await fixture.runWorker();
        await fixture.expectDone(entry, user: winner);
        expect(
          [existingResult, acceptError],
          [
            isNull,
            isA<InvitationWrongException>().having(
              (error) => error.reason,
              'invitation result',
              InvitationWrongReason.used,
            ),
          ],
        );
      },
    );

    for (final blocking in [false, true]) {
      test(
        blocking
            ? 'blocking during Unlink removes contacts and forwards and skips a queued link'
            : 'changing a vote during Unlink commits without losing the reciprocal vote',
        () async {
          final entry = await fixture.createInvite();
          expect(await fixture.accept(entry.code), InviteAcceptance.accepted);
          await fixture.runWorker();
          await fixture.expectDone(entry);
          final pending = blocking ? await fixture.createInvite() : null;
          if (pending != null) {
            expect(
              await fixture.accept(pending.code),
              InviteAcceptance.accepted,
            );
            await fixture.expectQueuedFor(pending, _joiner);
            // A removed contact is valid while the map entry is still linked.
            // The two calls can then meet directly on the shared vote rows.
            await fixture.seedForward();
            final contacts = getIt<ContactCase>();
            expect(
              await contacts.delete(viewerId: _owner, subjectId: _joiner),
              isTrue,
            );
            await contacts.set(
              viewerId: _joiner,
              subjectId: _owner,
              contactName: 'Saved neighbour',
            );
          }

          // The two transactions use different lock orders for the same
          // vote and trust pair. Give the vote writer's deadlock detector
          // priority so the caller that does not own a retry is exercised.
          await fixture.deferDeadlockDetection(
            on: 'AFTER UPDATE OF undone_at ON public.phantom_merge',
            when:
                "NEW.phantom_id = '${entry.id}' AND NEW.undone_at IS NOT NULL",
          );
          final (writeError, unlinkError) = await fixture.race(
            pauseOn: blocking
                ? 'AFTER DELETE ON public.vote_user'
                : 'AFTER UPDATE ON public.vote_user',
            when: "${blocking ? 'OLD' : 'NEW'}.subject = '$_owner'",
            beforePause: "SET LOCAL deadlock_timeout = '20ms';",
            second: () async {
              expect(
                await getIt<PhantomMergeCase>().unmerge(
                  ownerId: _owner,
                  phantomId: entry.id,
                ),
                isTrue,
              );
            },
            first: blocking
                ? () => getIt<UserBlockCase>().block(
                    blockerId: _owner,
                    blockedId: _joiner,
                    cascadeMode: 0,
                  )
                : () => getIt<UserTrustEdgeCase>().setUserVote(
                    subjectUserId: _owner,
                    objectUserId: _joiner,
                    amount: -1,
                  ),
          );

          expect((writeError, unlinkError), (null, null));
          expect(
            (await fixture.sql(
              'SELECT undone_at IS NOT NULL FROM public.phantom_merge WHERE phantom_id = @id',
              {'id': entry.id},
            )).single.single,
            isTrue,
          );
          final state = (await fixture.sql(
            '''
SELECT
  (SELECT count(*) FROM public.user_contact
     WHERE (viewer_id, subject_id) IN ((@owner, @user), (@user, @owner))),
  (SELECT count(*) FROM public.beacon_forward_edge
     WHERE (sender_id, recipient_id) IN ((@owner, @user), (@user, @owner))
       AND cancelled_at IS NULL),
  EXISTS (SELECT 1 FROM public.user_block
     WHERE blocker_id = @owner AND blocked_id = @user)
''',
            {'owner': _owner, 'user': _joiner},
          )).single.toList();
          expect(state, [0, 0, blocking]);
          if (pending != null) {
            await fixture.expectQueuedFor(pending, _joiner);
            await fixture.runWorker();
            await fixture.expectSkippedForBlock(pending);
            expect(await fixture.contacts(), isEmpty);
            expect(await fixture.activeForwards(), isEmpty);
            return;
          }

          final votes = await fixture.sql(
            '''
SELECT subject, object, amount FROM public.vote_user
WHERE (subject, object) IN ((@owner, @user), (@user, @owner))
ORDER BY subject
''',
            {'owner': _owner, 'user': _joiner},
          );
          // Unlink removes the outgoing vote when it commits last. When
          // the vote commits last, the explicit negative vote is kept.
          expect(
            votes,
            anyOf(
              equals([
                [_joiner, _owner, 1],
              ]),
              equals([
                [_owner, _joiner, -1],
                [_joiner, _owner, 1],
              ]),
            ),
          );
          expect(
            await fixture.sql(
              '''
SELECT subject, object FROM public.user_trust_edge
WHERE (subject, object) IN ((@owner, @user), (@user, @owner))
  AND target_w > 0
''',
              {'owner': _owner, 'user': _joiner},
            ),
            [
              [_joiner, _owner],
            ],
          );
        },
      );
    }
  }, skip: skip);
}

typedef _Entry = ({String id, String code});

final class _Database {
  _Database(this.writer, this.env);

  final Connection writer;
  final Env env;

  Future<Result> sql(String query, [Map<String, Object?> args = const {}]) =>
      writer.execute(
        Sql.named(query),
        parameters: args,
        timeout: _completionLimit,
      );

  Future<_Entry> createInvite({ConstellationAnchorPosition? position}) async {
    final phantoms = getIt<PhantomCase>();
    final id = await phantoms.create(
      ownerId: _owner,
      name: 'Private neighbour',
      position: position,
    );
    final code = await phantoms.saveInvite(
      ownerId: _owner,
      id: id,
      rotate: false,
    );
    return (id: id, code: code);
  }

  Future<List<Map<String, Object?>>> invitations(String id) async => (await sql(
    'SELECT * FROM public.invitation WHERE phantom_id = @id ORDER BY id',
    {'id': id},
  )).map((row) => row.toColumnMap()).toList();

  Future<InviteAcceptance> accept(String code) =>
      getIt<InvitationCase>().acceptAsExisting(code: code, userId: _joiner);

  Future<String> signUp(String code) async {
    final result = await getIt<CredentialAuthCase>().resolveOrCreate(
      type: CredentialType.emailOtp,
      identifier: _signupEmail,
      displayName: 'New neighbour',
      inviteId: code,
    );
    expect(result.isNewAccount, isTrue);
    return result.accountId;
  }

  Future<void> runWorker({
    String leaseOwner = 'contention-test-worker',
    DateTime? now,
  }) => getIt<PhantomMergeCase>()
      .runDue(
        leaseOwner: leaseOwner,
        clock: () => now ?? DateTime.timestamp(),
      )
      .timeout(_completionLimit);

  Future<void> expectDone(_Entry entry, {String user = _joiner}) async {
    final job = await sql(
      '''
SELECT state, user_id, attempts, last_error FROM public.phantom_merge_job
WHERE invitation_id = @code
''',
      {'code': entry.code},
    );
    expect(job, hasLength(1));
    expect(job.single[0], 'done');
    expect(job.single[1], user);
    expect(job.single[2], inInclusiveRange(1, 3));
    expect(job.single[3], isNull);
    expect(
      await sql(
        '''
SELECT user_id FROM public.phantom_merge WHERE phantom_id = @id
''',
        {'id': entry.id},
      ),
      [
        [user],
      ],
    );
  }

  Future<void> expectQueuedFor(_Entry entry, String user) async {
    expect(
      await sql(
        '''
SELECT phantom_id, user_id, state, attempts FROM public.phantom_merge_job
WHERE invitation_id = @code
''',
        {'code': entry.code},
      ),
      [
        [entry.id, user, 'queued', 0],
      ],
      reason:
          'The winning claim must create exactly one job for this invitation.',
    );
  }

  Future<void> expectSkippedForBlock(_Entry entry) async {
    expect(
      await sql(
        '''
SELECT state, reason, attempts, last_error, public.block_hides(owner_id, user_id)
FROM public.phantom_merge_job WHERE invitation_id = @code
''',
        {'code': entry.code},
      ),
      [
        ['skipped', 'blocked', 1, null, true],
      ],
    );
    expect(
      await sql(
        'SELECT id FROM public.phantom_merge WHERE phantom_id = @id',
        {'id': entry.id},
      ),
      isEmpty,
    );
  }

  Future<String> createPin() => getIt<PhantomCase>().create(
    ownerId: _owner,
    name: 'Another neighbour',
    position: _savedPin,
  );

  Future<void> movePin(String id) async {
    final elapsed = Stopwatch()..start();
    final result = await getIt<ConstellationAnchorCase>()
        .apply(
          viewerId: _owner,
          ops: [
            AnchorApplyOp(
              clientOpId: 'move-pin',
              kind: AnchorOpKind.upsert,
              target: ConstellationAnchorPhantomTarget(id),
              position: _movedPin,
            ),
          ],
        )
        .timeout(_completionLimit);
    expect(elapsed.elapsed, lessThanOrEqualTo(const Duration(seconds: 5)));
    expect(result.results.map((op) => op.status), [AnchorOpStatus.ok]);
  }

  Future<Result> pin(String kind, String id) => sql(
    '''
SELECT x_units, y_units FROM public.constellation_anchor
WHERE viewer_id = @owner AND target_kind = @kind AND target_id = @id
''',
    {'owner': _owner, 'kind': kind, 'id': id},
  );

  Future<int> pinRevision(String kind, String id) async =>
      (await sql(
            '''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = @owner AND target_kind = @kind AND target_id = @id
''',
            {'owner': _owner, 'kind': kind, 'id': id},
          )).singleOrNull?.single
          as int? ??
      0;

  Future<Result> contacts() => sql('''
SELECT viewer_id, subject_id, contact_name FROM public.user_contact
WHERE (viewer_id, subject_id) IN ((@owner, @user), (@user, @owner))
''', _pair);

  Future<Result> activeForwards() => sql('''
SELECT sender_id, recipient_id FROM public.beacon_forward_edge
WHERE (sender_id, recipient_id) IN ((@owner, @user), (@user, @owner))
  AND cancelled_at IS NULL
''', _pair);

  Future<void> block() => getIt<UserBlockCase>().block(
    blockerId: _owner,
    blockedId: _joiner,
    cascadeMode: 0,
  );

  Future<Result> lease(_Entry entry) => sql(
    '''
SELECT state, lease_owner, attempts FROM public.phantom_merge_job
WHERE invitation_id = @code
''',
    {'code': entry.code},
  );

  Future<void> waitForLease(
    _Entry entry,
    String worker,
    Future<void> running,
  ) async {
    var completed = false;
    unawaited(
      running.then<void>(
        (_) {
          completed = true;
        },
        onError: (Object _) {
          completed = true;
        },
      ),
    );
    final clock = Stopwatch()..start();
    while (!completed && clock.elapsed < _completionLimit) {
      if ((await lease(entry)).single[1] == worker) return;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    fail('The replacement worker did not claim the expired job.');
  }

  Future<void> seedForward() async {
    await seedRequest();
    await sql(
      '''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@request, @owner, @user)
''',
      {..._pair, 'request': _request},
    );
  }

  Future<void> seedRequest() async {
    await sql(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy, is_discoverable, published_at)
VALUES (@request, @owner, 'A request', '', @status, @kind, 1, false, now())
''',
      {
        'owner': _owner,
        'request': _request,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
      },
    );
  }

  Future<Result> allVotes() =>
      sql('SELECT subject, object, amount FROM public.vote_user');

  Future<Result> activeTrust() => sql('''
SELECT subject, object FROM public.user_trust_edge WHERE target_w > 0
''');

  Future<void> expectUndone(_Entry entry) async {
    expect(
      await sql(
        'SELECT undone_at IS NOT NULL FROM public.phantom_merge WHERE phantom_id = @id',
        {'id': entry.id},
      ),
      [
        [true],
      ],
    );
  }

  Future<void> countAcceptAttempts(
    String code, {
    bool failFirstCommit = false,
  }) async {
    // A sequence survives transaction rollback, so it counts the failed
    // attempt as well as the eventual successful claim.
    await writer.execute('''
CREATE SEQUENCE public.test_accept_attempts;
CREATE FUNCTION public.test_accept_conflict() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  ${failFirstCommit ? """
  IF nextval('public.test_accept_attempts') = 1 THEN
    RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'test concurrent accept';
  END IF;
  """ : """
  PERFORM nextval('public.test_accept_attempts');
  SET LOCAL deadlock_timeout = '20ms';
  """}
  RETURN NEW;
END;
\$\$;
CREATE ${failFirstCommit ? 'CONSTRAINT ' : ''}TRIGGER test_accept_conflict
AFTER UPDATE ON public.invitation
${failFirstCommit ? 'DEFERRABLE INITIALLY DEFERRED' : ''}
FOR EACH ROW WHEN (NEW.id = '$code' AND OLD.invited_id IS NULL AND NEW.invited_id IS NOT NULL)
EXECUTE FUNCTION public.test_accept_conflict();
''', queryMode: QueryMode.simple);
    addTearDown(
      () => writer.execute('DROP SEQUENCE public.test_accept_attempts'),
    );
    addTearDown(
      () =>
          writer.execute('DROP FUNCTION public.test_accept_conflict() CASCADE'),
    );
  }

  Future<int> acceptAttempts() async =>
      (await sql('''
SELECT CASE WHEN is_called THEN last_value ELSE 0 END FROM public.test_accept_attempts
''')).single.single!
          as int;

  Future<void> raceVotesAgainstAccept(_Entry entry) async {
    const ownerGate = _gateKey + 1;
    const joinerGate = _gateKey + 2;
    await writer.execute('''
CREATE FUNCTION public.test_pause_vote() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  PERFORM pg_advisory_xact_lock(CASE NEW.subject
    WHEN '$_owner' THEN $ownerGate::bigint ELSE $joinerGate::bigint END);
  RETURN NEW;
END;
\$\$;
CREATE TRIGGER test_pause_vote AFTER INSERT ON public.vote_user
FOR EACH ROW WHEN (NEW.object = '$_other' AND NEW.subject IN ('$_owner', '$_joiner'))
EXECUTE FUNCTION public.test_pause_vote();
''', queryMode: QueryMode.simple);
    addTearDown(
      () => writer.execute('DROP FUNCTION public.test_pause_vote() CASCADE'),
    );

    final gate = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    addTearDown(gate.close);
    final pending = <Future<Object?>>[];
    try {
      await gate.runTx((tx) async {
        for (final key in [ownerGate, joinerGate]) {
          await tx.execute(
            Sql.named('SELECT pg_advisory_xact_lock(@key::bigint)'),
            parameters: {'key': key},
          );
        }
        final votes = getIt<UserTrustEdgeCase>();
        for (final voter in [_owner, _joiner]) {
          pending.add(
            _outcome(
              () => votes.setUserVote(
                subjectUserId: voter,
                objectUserId: _other,
                amount: 1,
              ),
            ),
          );
        }
        final ownerVoter = await waitForAdvisoryWaiter(ownerGate);
        await waitForAdvisoryWaiter(joinerGate);
        final accepting = _outcome(() async {
          expect(await accept(entry.code), InviteAcceptance.accepted);
        });
        pending.add(accepting);
        await waitForBlockedBy(ownerVoter, accepting);
      });
    } finally {
      final errors = await Future.wait(pending).timeout(_completionLimit);
      expect(errors, everyElement(isNull));
    }
  }

  Future<int> waitForAdvisoryWaiter(int key) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < _completionLimit) {
      final rows = await sql(
        '''
SELECT pid FROM pg_locks
WHERE locktype = 'advisory' AND NOT granted AND classid = 0 AND objid = @key
  AND objsubid = 1 AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
''',
        {'key': key},
      );
      if (rows.isNotEmpty) return rows.single.single! as int;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    fail('No vote reached its advisory lock barrier.');
  }

  Future<void> deferDeadlockDetection({
    required String on,
    required String when,
  }) async {
    await writer.execute('''
CREATE FUNCTION public.test_set_deadlock_timeout() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  SET LOCAL deadlock_timeout = '10s';
  RETURN NEW;
END;
\$\$;
CREATE TRIGGER test_set_deadlock_timeout $on FOR EACH ROW
WHEN ($when) EXECUTE FUNCTION public.test_set_deadlock_timeout();
''', queryMode: QueryMode.simple);
    addTearDown(
      () => writer.execute(
        'DROP FUNCTION public.test_set_deadlock_timeout() CASCADE',
      ),
    );
  }

  Future<(Object?, Object?)> race({
    required String pauseOn,
    required Future<void> Function() first,
    required Future<void> Function() second,
    String? when,
    String beforePause = '',
    String forEach = 'ROW',
    bool requireSecondWait = false,
    bool requireSecondCompletion = false,
  }) async {
    await writer.execute('''
CREATE FUNCTION public.test_pause_graph_write() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  $beforePause
  PERFORM pg_advisory_xact_lock($_gateKey);
  RETURN NEW;
END;
\$\$;
CREATE TRIGGER zz_test_pause_graph_write $pauseOn FOR EACH $forEach
${when == null ? '' : 'WHEN ($when)'}
EXECUTE FUNCTION public.test_pause_graph_write();
''', queryMode: QueryMode.simple);
    addTearDown(
      () => writer.execute(
        'DROP FUNCTION public.test_pause_graph_write() CASCADE',
      ),
    );
    final gate = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    addTearDown(gate.close);
    final gatePid =
        (await gate.execute('SELECT pg_backend_pid()')).single.single! as int;

    Future<Object?>? firstResult;
    Future<Object?>? secondResult;
    try {
      await gate.runTx((tx) async {
        await tx.execute('SELECT pg_advisory_xact_lock($_gateKey)');
        firstResult = _outcome(first);
        final firstPid = await waitForBlockedBy(gatePid, firstResult!);
        secondResult = _outcome(second);
        final secondPid = await waitForBlockedBy(
          firstPid!,
          secondResult!,
          allowCompletion: !requireSecondWait,
        );
        if (requireSecondCompletion) {
          expect(
            secondPid,
            isNull,
            reason: 'The competing call must finish while the first is paused.',
          );
        }
      });
    } finally {
      await Future.wait([
        ?firstResult,
        ?secondResult,
      ]).timeout(_completionLimit);
    }
    return (await firstResult!, await secondResult!);
  }

  Future<int?> waitForBlockedBy(
    int blocker,
    Future<Object?> outcome, {
    bool allowCompletion = false,
  }) async {
    var finished = false;
    unawaited(outcome.then((_) => finished = true));
    final clock = Stopwatch()..start();
    while (!finished && clock.elapsed < _completionLimit) {
      final rows = await sql(
        '''
SELECT pid FROM pg_stat_activity
WHERE datname = current_database() AND @blocker = ANY(pg_blocking_pids(pid))
''',
        {'blocker': blocker},
      );
      if (rows.isNotEmpty) return rows.single.single! as int;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    if (finished) {
      if (allowCompletion) return null;
      fail(
        'Caller completed before reaching the lock barrier: ${await outcome}',
      );
    }
    fail('Caller did not reach the lock barrier behind backend $blocker.');
  }
}

Future<Object?> _outcome(Future<void> Function() operation) async {
  try {
    await operation().timeout(_completionLimit);
    return null;
  } on Object catch (error) {
    return error;
  }
}
