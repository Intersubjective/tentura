@Tags(['pg'])
library;

import 'dart:convert';
// The VM runner supports mirrors, which the Flutter workspace analyzer hides.
// Replace this lookup with the typed case once the case is available.
// ignore: uri_does_not_exist
import 'dart:mirrors' as vm;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Handler, Request;
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart' show TenturaDb;
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/invite_acceptance.dart';
import 'package:tentura_server/domain/entity/person_tag.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/people_tags_repository_port.dart';
import 'package:tentura_server/domain/port/phantom_merge_wake_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/contact_case.dart';
import 'package:tentura_server/domain/use_case/credential_auth_case.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/phantom_case.dart';
import 'package:tentura_server/domain/use_case/phantom_merge_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/owner_graph_contention.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';
import '../../support/session_database_di_harness.dart';

const _owner = 'U781c00000001';
const _person = 'U781c00000002';
const _otherPerson = 'U781c00000003';
const _initialName = 'Neighbour from the old address';
const _currentName = 'Neighbour from the new address';
const _savedName = 'Name already in contacts';

const _phantomPosition = ConstellationAnchorPosition(
  xUnits: -7.25,
  yUnits: 3.5,
  coordinateSpaceVersion: 1,
);
const _personPosition = ConstellationAnchorPosition(
  xUnits: 11.5,
  yUnits: -4.75,
  coordinateSpaceVersion: 1,
);

enum _Origin {
  inviteNew(1),
  inviteExisting(2),
  manualLink(3);

  const _Origin(this.code);

  final int code;
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PHANTOM_MERGE_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_merge',
    useDevBindings: true,
  );
  final skip = await pgSkipReason(target);

  group('Linking a private map entry to a Tentura account', () {
    late _Fixture fixture;

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
      // Invites must be accepted and committed, with merge execution still
      // under control of the test.
      getIt.registerSingleton<PhantomMergeWakePort>(
        const PhantomMergeWakePort.disabled(),
      );
      await configureSessionDatabaseTestGraph(target.databaseEnv);
      await expectDefaultOwnerScopeEnforcement(getIt<TenturaDb>());
      final api = _UnlinkApi(
        (await getIt.getAsync<RootRouter>()).routeHandler(),
      );
      fixture = _Fixture(session.writer, api);
    });

    setUp(() => fixture.reset());

    for (final hasPersonPin in [false, true]) {
      test(
        hasPersonPin
            ? 'linking an unpinned entry records the merge and keeps the account pin'
            : 'linking two unpinned entries records the merge and leaves both unpinned',
        () async {
          if (hasPersonPin) {
            await fixture.pin(
              const ConstellationAnchorPersonTarget(_person),
              _personPosition,
            );
          }
          final pinsBefore = await fixture.pinRows();
          expect(pinsBefore, hasLength(hasPersonPin ? 1 : 0));
          final phantomBefore = await fixture.phantomRow();

          await fixture.merge();

          expect(await fixture.pinRows(), pinsBefore);
          final undo = await fixture.expectRecordedMerge(
            _person,
            _Origin.manualLink,
            phantomBefore,
          );
          expect(
            undo['pin'],
            isNull,
            reason: 'There is no pin change to undo.',
          );
        },
      );

      test(
        hasPersonPin
            ? 'a private pin moves the existing account pin and records both prior positions'
            : 'a private pin becomes the account pin and records that the account had none',
        () async {
          const personTarget = ConstellationAnchorPersonTarget(_person);
          await fixture.pin(personTarget, _personPosition);
          if (!hasPersonPin) {
            await getIt<ScopedConstellationAnchorRepositoryPort>().resetAll(
              viewerId: _owner,
              clientOpId: 'clear-account-pin',
            );
          }
          await fixture.pin(
            ConstellationAnchorPhantomTarget(fixture.phantom),
            _phantomPosition,
          );
          final pinsBefore = await fixture.pinRows();
          expect(
            pinsBefore.map((row) => row['target_kind']),
            hasPersonPin ? ['PERSON', 'PHANTOM'] : ['PHANTOM'],
          );
          final before = await fixture.watermarks();
          expect(before.keys, unorderedEquals(['PERSON', 'PHANTOM']));

          await fixture.merge();

          final pinsAfter = await fixture.pinRows();
          expect(
            pinsAfter,
            [
              allOf([
                containsPair('target_kind', 'PERSON'),
                containsPair('target_id', _person),
                containsPair('person_id', _person),
                containsPair('phantom_id', isNull),
                containsPair('tombstone_at', isNull),
                containsPair('x_units', _phantomPosition.xUnits),
                containsPair('y_units', _phantomPosition.yUnits),
                containsPair('coordinate_space_version', 1),
                if (hasPersonPin) containsPair('id', pinsBefore.first['id']),
              ]),
            ],
            reason:
                'Only the live account pin should remain at the old position.',
          );
          if (hasPersonPin) {
            final placedBefore = pinsBefore.first['placed_at'];
            if (placedBefore is! DateTime) {
              fail('Expected a stored placement time.');
            }
            expect(
              pinsAfter.single['placed_at'],
              isA<DateTime>().having(
                (placedAt) => placedAt.isAfter(placedBefore),
                'placed after the original pin',
                isTrue,
              ),
            );
          }
          final after = await fixture.watermarks();
          expect(after, {
            for (final kind in before.keys) kind: greaterThan(before[kind]!),
          });

          final undo = await fixture.undo();
          expect(undo['pin'], {
            'phantomPosition': _phantomPosition.toFixtureMap(),
            'previousPersonPosition': hasPersonPin
                ? _personPosition.toFixtureMap()
                : null,
            'personWatermark': isA<int>().having(
              (revision) => revision,
              'committed account pin revision',
              after['PERSON'],
            ),
          });
        },
      );
    }

    test('tags retain existing member identities and hide the linked entry '
        'while recording the original and added memberships', () async {
      final t1 = await fixture.tag('Neighbours', [fixture.phantom, _person]);
      final t2 = await fixture.tag('Volunteers', [fixture.phantom]);
      final originalMemberships = await fixture.phantomMemberships();
      final before = await fixture.personMemberships();
      expect(
        originalMemberships.map((row) => row['tag_id']),
        unorderedEquals([t1, t2]),
      );
      expect(before.single['tag_id'], t1);
      expect(await fixture.visibleMemberships(), {
        t1: unorderedEquals([fixture.phantom, _person]),
        t2: [fixture.phantom],
      });
      expect(await fixture.tagCounts(), {t1: 2, t2: 1});

      await fixture.merge();

      final people = await fixture.personMemberships();
      expect(people.map((row) => row['tag_id']), unorderedEquals([t1, t2]));
      expect(people.singleWhere((row) => row['tag_id'] == t1), before.single);
      final added = people.singleWhere((row) => row['tag_id'] == t2);
      expect(await fixture.phantomMemberships(), originalMemberships);
      expect(await fixture.visibleMemberships(), {
        t1: [_person],
        t2: [_person],
      });
      expect(await fixture.tagCounts(), {t1: 1, t2: 1});

      final undo = await fixture.undo();
      expect(undo['insertedMembershipIds'], [added['membership_id']]);
      expect(
        undo['phantomMemberships'],
        unorderedEquals([
          for (final row in originalMemberships)
            {
              ...row,
              'added_at': isA<String>().having(
                DateTime.tryParse,
                'original membership timestamp',
                row['added_at'],
              ),
            },
        ]),
      );
    });

    test(
      'a block committed after merge admission prevents the tag copy',
      () async {
        await fixture.tag('Neighbours', [fixture.phantom]);
        final membershipBefore = await fixture.phantomMemberships();
        final phantomBefore = await fixture.phantomRow();
        expect(membershipBefore, hasLength(1));
        expect(await fixture.personMemberships(), isEmpty);
        expect(await fixture.blockHides(_person), isFalse);

        final env = target.databaseEnv;
        final gate = await Connection.open(
          env.pgEndpoint,
          settings: env.pgEndpointSettings,
        );
        addTearDown(gate.close);
        Future<Object?>? merge;
        try {
          await gate.runTx((tx) async {
            // The plan writes the audit row after the guards and before tags.
            // Hold that write until another session commits the block.
            await tx.execute(
              'LOCK TABLE public.phantom_merge IN SHARE MODE',
              timeout: kStableStateWait,
            );
            final gatePid =
                (await tx.execute('SELECT pg_backend_pid()')).single.single!
                    as int;
            final pending = fixture.merge()..ignore();
            merge = pending;
            await fixture.waitForMergeAuditWrite(gatePid, pending);
            await fixture.block(_owner, _person);
            expect(await fixture.blockHides(_person), isTrue);
          });
        } finally {
          // Always release the lock before draining the merge.
          await merge?.timeout(kCompletionWait);
        }

        final undo = await fixture.expectRecordedMerge(
          _person,
          _Origin.manualLink,
          phantomBefore,
        );
        expect(await fixture.personMemberships(), isEmpty);
        expect(await fixture.phantomMemberships(), membershipBefore);
        expect(undo['insertedMembershipIds'], isEmpty);
      },
    );

    for (final origin in [_Origin.inviteNew, _Origin.inviteExisting]) {
      test(
        origin == _Origin.inviteNew
            ? 'a new account gets the current map name after signup with its invite'
            : 'an existing account gets the current map name after accepting its invite',
        () async {
          if (origin == _Origin.inviteExisting) {
            await fixture.saveContactName();
          }
          final code = await fixture.createInvite();
          final user = await fixture.accept(code, origin);
          final priorName = origin == _Origin.inviteNew ? null : _savedName;
          expect(await fixture.contactName(user), priorName);
          expect(await fixture.liveInvites(), isEmpty);
          await getIt<PhantomCase>().update(
            ownerId: _owner,
            id: fixture.phantom,
            name: _currentName,
          );
          final before = await fixture.phantomRow();
          expect(before['display_name'], _currentName);
          expect(before['merged_at'], isNull);

          await fixture.merge(user: user, origin: origin);

          expect(await fixture.contactName(user), _currentName);
          final undo = await fixture.expectRecordedMerge(user, origin, before);
          expect(undo['contactName'], {
            'before': priorName,
            'written': _currentName,
          });
        },
      );
    }

    test('a manual link keeps the owner’s saved contact name and records it '
        'without a replacement', () async {
      await fixture.saveContactName();
      final contacts = await fixture.contactRows();
      expect(contacts.single['contact_name'], _savedName);

      await fixture.merge();

      expect(await fixture.contactRows(), contacts);
      final undo = await fixture.undo();
      expect(undo['contactName'], {'before': _savedName, 'written': null});
    });

    test('a manual link supplies a missing contact name and removes the '
        'entry’s unused invite', () async {
      final code = await fixture.createInvite();
      final before = await fixture.phantomRow();
      expect(await fixture.contactName(_person), isNull);
      expect((await fixture.liveInvites()).single['id'], code);
      expect(before['merged_at'], isNull);

      await fixture.merge();

      expect(
        {
          'contact name': await fixture.contactName(_person),
          'live invitations': await fixture.liveInvites(),
          'original invitation': await fixture.inviteById(code),
        },
        {
          'contact name': _initialName,
          'live invitations': isEmpty,
          'original invitation': isEmpty,
        },
      );
      final undo = await fixture.expectRecordedMerge(
        _person,
        _Origin.manualLink,
        before,
      );
      expect(undo['contactName'], {'before': null, 'written': _initialName});
    });

    test('the merge commits with owner scope enforcement and records a '
        'merge attention event for just the owner', () async {
      final before = await fixture.phantomRow();
      expect(await fixture.mergeAttentionEvents(), isEmpty);

      await fixture.merge();

      await fixture.expectRecordedMerge(_person, _Origin.manualLink, before);
      final events = await fixture.mergeAttentionEvents();
      expect(
        events,
        hasLength(1),
        reason: 'The merge must emit exactly one event with one recipient.',
      );
      expect(events.single['target_id'], fixture.phantom);
      expect(events.single['account_id'], _owner);
    });

    for (final (description, reason, user, blocked, prepare)
        in <(String, Matcher, String, bool, Future<void> Function())>[
          (
            'an account the owner blocked',
            equals('blocked'),
            _person,
            true,
            () => fixture.block(_owner, _person),
          ),
          (
            'an account that blocked the owner',
            equals('blocked'),
            _person,
            true,
            () => fixture.block(_person, _owner),
          ),
          (
            'an already linked entry',
            matches(RegExp('inactive', caseSensitive: false)),
            _person,
            false,
            () => fixture.makeInactive(previousUser: _otherPerson),
          ),
          (
            'an orphaned entry',
            matches(RegExp('inactive', caseSensitive: false)),
            _person,
            false,
            () => fixture.makeInactive(),
          ),
          (
            'the owner’s own account',
            matches(
              RegExp(
                'self|own account|owner.*target|target.*owner|same.*(account|user)',
                caseSensitive: false,
              ),
            ),
            _owner,
            false,
            () async {},
          ),
        ]) {
      test('rejects $description and preserves the owner’s data', () async {
        await fixture.pin(
          ConstellationAnchorPhantomTarget(fixture.phantom),
          _phantomPosition,
        );
        await fixture.pin(
          const ConstellationAnchorPersonTarget(_person),
          _personPosition,
        );
        await fixture.tag('Neighbours', [fixture.phantom]);
        await fixture.createInvite();
        await fixture.saveContactName();
        await prepare();
        expect(
          await fixture.blockHides(user),
          blocked,
          reason: 'Check block_hides with the owner and this merge target.',
        );

        final before = await fixture.guardSnapshot();
        final outcome = await fixture.merge(user: user);

        expect(await fixture.guardSnapshot(), before);
        expect(
          _guardReason(outcome),
          reason,
          reason: 'The merge must explicitly reject $description.',
        );
      });
    }

    group('Unlinking a merged phantom', () {
      Future<void> linkManually() async {
        await fixture.seedOutgoingVote();
        await fixture.api.link(fixture.phantom);
        await fixture.expectLinkedForUndo(_Origin.manualLink);
      }

      Future<void> unlink() async {
        final reply = await fixture.api.unmerge(fixture.phantom);
        expect(reply, {
          'data': {'phantomUnmerge': true},
        });
      }

      test('restores the map entry in its tags and removes only copied '
          'account memberships', () async {
        final shared = await fixture.tag('Shared tag', [
          fixture.phantom,
          _person,
        ]);
        final copied = await fixture.tag('Copied tag', [fixture.phantom]);
        final original = (await fixture.personMemberships()).single;
        expect(original['tag_id'], shared);

        await linkManually();

        final inserted = (await fixture.personMemberships()).singleWhere(
          (row) => row['tag_id'] == copied,
        );
        expect((await fixture.undo())['insertedMembershipIds'], [
          inserted['membership_id'],
        ]);
        expect(await fixture.visibleMemberships(), {
          shared: [_person],
          copied: [_person],
        });

        await unlink();

        expect(await fixture.visibleMemberships(), {
          shared: unorderedEquals([fixture.phantom, _person]),
          copied: [fixture.phantom],
        });
        expect(await fixture.personMemberships(), [original]);
      });

      test(
        'keeps an account membership removed and re-added after linking',
        () async {
          final tag = await fixture.tag('Neighbours', [fixture.phantom]);
          await linkManually();
          final inserted = (await fixture.personMemberships()).single;

          await fixture.changeAccountMembership(tag, add: false);
          expect(await fixture.personMemberships(), isEmpty);
          await fixture.changeAccountMembership(tag, add: true);
          final readded = (await fixture.personMemberships()).single;
          expect(readded['membership_id'], isNot(inserted['membership_id']));

          await unlink();

          expect(await fixture.personMemberships(), [readded]);
          expect(await fixture.visibleMemberships(), {
            tag: unorderedEquals([fixture.phantom, _person]),
          });
        },
      );

      for (final hadAccountPin in [false, true]) {
        test(
          hadAccountPin
              ? 'restores both pins to their original positions and advances both watermarks'
              : 'restores the private pin, removes the copied account pin and advances both watermarks',
          () async {
            if (hadAccountPin) {
              await fixture.pin(
                const ConstellationAnchorPersonTarget(_person),
                _personPosition,
              );
            }
            await fixture.pin(
              ConstellationAnchorPhantomTarget(fixture.phantom),
              _phantomPosition,
            );
            await linkManually();
            expect(await fixture.livePinPositions(), {
              ('PERSON', _person): _phantomPosition.toFixtureMap(),
            });
            final before = await fixture.watermarks();

            await unlink();

            expect(await fixture.livePinPositions(), {
              ('PHANTOM', fixture.phantom): _phantomPosition.toFixtureMap(),
              if (hadAccountPin)
                ('PERSON', _person): _personPosition.toFixtureMap(),
            });
            await fixture.expectAdvancedWatermarks(before);
          },
        );
      }

      test('keeps a later account pin move without restoring the private '
          'pin and advances both watermarks', () async {
        await fixture.pin(
          ConstellationAnchorPhantomTarget(fixture.phantom),
          _phantomPosition,
        );
        await linkManually();
        final linked = await fixture.watermarks();
        await fixture.pin(
          const ConstellationAnchorPersonTarget(_person),
          _personPosition,
        );
        final moved = await fixture.livePinPositions();
        expect(moved, {('PERSON', _person): _personPosition.toFixtureMap()});
        final before = await fixture.watermarks();
        expect(before['PERSON'], greaterThan(linked['PERSON']!));

        await unlink();

        expect(await fixture.livePinPositions(), moved);
        await fixture.expectAdvancedWatermarks(before);
      });

      for (final oldName in [null, 'Old']) {
        test(
          oldName == null
              ? 'removes the invite-written contact name when there was no previous name'
              : 'restores the previous contact name after an invitation link',
          () async {
            if (oldName != null) await fixture.editContactName(oldName);
            expect(await fixture.contactName(_person), oldName);
            await fixture.linkByAcceptedInvite();
            expect(await fixture.contactName(_person), _initialName);

            await unlink();

            expect(await fixture.contactName(_person), oldName);
            if (oldName == null) expect(await fixture.contactRows(), isEmpty);
          },
        );
      }

      test(
        'keeps a contact name the owner edited after an invitation link',
        () async {
          await fixture.editContactName('Old');
          await fixture.linkByAcceptedInvite();
          expect(await fixture.contactName(_person), _initialName);
          await fixture.editContactName('Updated by owner');

          await unlink();

          expect(await fixture.contactName(_person), 'Updated by owner');
        },
      );

      for (final hadVote in [false, true]) {
        test(
          hadVote
              ? 'withdraws pre-existing outgoing trust and re-projects the invite pair'
              : 'withdraws invite-created outgoing trust and keeps the reverse vote',
          () async {
            if (hadVote) await fixture.seedOutgoingVote();
            final priorVote = await fixture.pairVotes();
            expect(priorVote, hasLength(hadVote ? 1 : 0));
            await fixture.linkByAcceptedInvite();
            final linkedVotes = await fixture.pairVotes();
            expect(linkedVotes.map((row) => row['subject']), [_owner, _person]);
            if (hadVote) expect(linkedVotes.first, priorVote.single);
            final linkedProjection = await fixture.projectedTrust(
              fixture.writer,
            );
            final withoutVote = await fixture.projectionWithoutOutgoingVote();
            expect(linkedProjection, isNot(withoutVote));
            expect(await fixture.pairVotes(), linkedVotes);

            await unlink();

            expect(await fixture.pairVotes(), [linkedVotes.last]);
            expect(await fixture.projectedTrust(fixture.writer), withoutVote);
          },
        );
      }

      test(
        'withdraws outgoing trust after an invitation creates an account',
        () async {
          final user = await fixture.linkByAcceptedInvite(
            origin: _Origin.inviteNew,
          );
          final linkedVotes = await fixture.pairVotes(user: user);
          expect(
            linkedVotes.map((row) => row['subject']),
            unorderedEquals([_owner, user]),
          );
          final reverse = linkedVotes.singleWhere(
            (row) => row['subject'] == user,
          );

          await unlink();

          expect(await fixture.pairVotes(user: user), [reverse]);
        },
      );

      test('preserves outgoing trust after a manual link', () async {
        await linkManually();
        final before = await fixture.pairVotes();
        expect(before.single['subject'], _owner);

        await unlink();

        expect(await fixture.pairVotes(), before);
      });

      test(
        'clears the active link and marks its audit record undone',
        () async {
          await linkManually();
          final previous = (await fixture.mergeRows()).single;

          await unlink();

          expect(
            await fixture.phantomRow(),
            allOf(
              containsPair('merged_user_id', isNull),
              containsPair('merged_at', isNull),
              containsPair('merge_origin', isNull),
              containsPair('current_merge_id', isNull),
            ),
          );
          expect(await fixture.mergeRows(), [
            allOf(
              containsPair('id', previous['id']),
              containsPair('undone_at', isA<DateTime>()),
            ),
          ]);
        },
      );

      test('leaves the private entry without a live invite until a new one is '
          'requested', () async {
        final oldCode = await fixture.api.ensureInvite(fixture.phantom);
        expect((await fixture.liveInvites()).single['id'], oldCode);
        await linkManually();
        expect(await fixture.liveInvites(), isEmpty);

        await unlink();

        expect(await fixture.liveInvites(), isEmpty);
        final newCode = await fixture.api.ensureInvite(fixture.phantom);
        expect(newCode, isNot(oldCode));
        expect((await fixture.liveInvites()).single['id'], newCode);
      });

      test(
        'returns not-found to another account and preserves the merge and account data',
        () async {
          await fixture.prepareInviteLinkWithTagsAndPin();
          final before = await fixture.unlinkSnapshot();

          final reply = await fixture.api.unmerge(
            fixture.phantom,
            actor: _otherPerson,
          );

          expect(
            await fixture.unlinkSnapshot(),
            before,
            reason:
                'The merge, copied membership, account pin and contact name '
                'must survive the rejected unlink.',
          );
          _expectUnlinkRefused(reply, containsPair('code', '1002'));
        },
      );

      test('refuses to reactivate an entry at the cap and preserves the '
          'entire invitation link', () async {
        await fixture.prepareInviteLinkWithTagsAndPin();
        await fixture.seedActiveEntriesAtCap();
        expect(await fixture.activeEntryCount(), 200);
        final before = await fixture.unlinkSnapshot();

        final reply = await fixture.api.unmerge(fixture.phantom);

        expect(await fixture.activeEntryCount(), 200);
        expect(await fixture.unlinkSnapshot(), before);
        _expectUnlinkRefused(
          reply,
          containsPair('reason', 'phantom_cap_reached'),
        );
      });

      test(
        'refuses to reactivate a map entry whose linked account was erased',
        () async {
          await linkManually();
          final linked = await fixture.phantomRow();

          await fixture.eraseLinkedAccount();
          final orphan = await fixture.phantomRow();
          final orphanMergeRows = await fixture.mergeRows();
          expect(
            orphan,
            allOf(
              containsPair('merged_at', linked['merged_at']),
              containsPair('merge_origin', linked['merge_origin']),
              containsPair('merged_user_id', isNull),
              containsPair('current_merge_id', isNull),
            ),
          );
          expect(
            orphanMergeRows,
            isEmpty,
            reason: 'Account erasure cascades to the merge audit record (§3).',
          );

          final reply = await fixture.api.unmerge(fixture.phantom);

          expect(await fixture.phantomRow(), orphan);
          expect(await fixture.mergeRows(), orphanMergeRows);
          _expectUnlinkRefused(
            reply,
            containsPair('code', allOf(isA<String>(), isNot('1000'))),
          );
        },
      );
    });
  }, skip: skip);
}

typedef _Merge =
    Future<Object?> Function({
      required String ownerId,
      required String phantomId,
      required String userId,
      required int origin,
    });

void _expectUnlinkRefused(Map<String, Object?> reply, Matcher extensions) {
  expect(reply['errors'], [
    containsPair('extensions', extensions),
  ], reason: jsonEncode(reply));
  expect((reply['data'] as Map<String, Object?>?)?['phantomUnmerge'], isNull);
}

final class _UnlinkApi {
  const _UnlinkApi(this._handler);

  final Handler _handler;

  Future<void> link(String phantom) async {
    final reply = await _post(
      r'mutation Link($phantomId: String!, $userId: String!) { '
      r'phantomLink(phantomId: $phantomId, userId: $userId) }',
      {'phantomId': phantom, 'userId': _person},
    );
    expect(reply, {
      'data': {'phantomLink': true},
    });
  }

  Future<String> ensureInvite(String phantom) async {
    final reply = await _post(
      r'mutation EnsureInvite($id: String!) { phantomInviteEnsure(id: $id) }',
      {'id': phantom},
    );
    expect(reply['errors'], isNull, reason: jsonEncode(reply));
    final data = reply['data']! as Map<String, Object?>;
    return data['phantomInviteEnsure']! as String;
  }

  Future<Map<String, Object?>> unmerge(
    String phantom, {
    String actor = _owner,
  }) => _post(
    r'mutation Unlink($phantomId: String!) { '
    r'phantomUnmerge(phantomId: $phantomId) }',
    {'phantomId': phantom},
    actor: actor,
  );

  Future<Map<String, Object?>> _post(
    String query,
    Map<String, Object?> variables, {
    String actor = _owner,
  }) async {
    final token = getIt<AuthCase>().issueAccessToken(actor).rawToken;
    final response = await _handler(
      Request(
        'POST',
        Uri.parse('http://127.0.0.1:2080/api/v2/graphql'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode({'query': query, 'variables': variables}),
      ),
    );
    final body = await response.readAsString();
    expect(response.statusCode, 200, reason: body);
    return jsonDecode(body) as Map<String, Object?>;
  }
}

// Resolve the production case at runtime while it has no importable API.
// Check the tear-off before calling it through Dart's named-argument syntax.
_Merge _resolveMerge() {
  final declaration =
      vm
              .currentMirrorSystem()
              .libraries[Uri.parse(
                'package:tentura_server/domain/use_case/phantom_merge_case.dart',
              )]
              ?.declarations[#PhantomMergeCase]
          as vm.ClassMirror?;
  if (declaration == null) {
    fail('PhantomMergeCase is unavailable for linking an entry to an account.');
  }
  final caseType = declaration.reflectedType;
  expect(
    getIt.isRegistered<Object>(type: caseType),
    isTrue,
    reason: 'The server must expose the account merge through its use case.',
  );
  final mergeCase = getIt.get<Object>(type: caseType);
  final Object? merge = vm.reflect(mergeCase).getField(#merge).reflectee;
  if (merge is! _Merge) {
    fail(
      'PhantomMergeCase.merge does not expose the expected account-linking call.',
    );
  }
  return merge;
}

String _guardReason(Object? outcome) {
  if (outcome == null) fail('The merge returned no guard-failure result.');
  final Object? reason = vm.reflect(outcome).getField(#reason).reflectee;
  return switch (reason) {
    final String value => value,
    final Enum value => value.name,
    _ => fail('The guard-failure result does not name a reason.'),
  };
}

final class _Fixture {
  _Fixture(this.writer, this.api);

  final Connection writer;
  final _UnlinkApi api;
  late String phantom;
  int _nextOperation = 0;

  Future<Result> _sql(
    String statement, [
    Map<String, Object?> parameters = const {},
  ]) => writer.execute(Sql.named(statement), parameters: parameters);

  Future<List<Map<String, Object?>>> _rows(
    String statement, [
    Map<String, Object?> parameters = const {},
  ]) async => (await _sql(
    statement,
    parameters,
  )).map((row) => row.toColumnMap()).toList();

  Future<void> reset() async {
    await writer.execute(
      'TRUNCATE TABLE public."user", public.attention_occurrence CASCADE',
    );
    for (final (i, id) in [_owner, _person, _otherPerson].indexed) {
      await _sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
        {'id': id, 'key': pgTestPublicKey('phantommerge', i + 1)},
      );
    }
    phantom = await getIt<PhantomCase>().create(
      ownerId: _owner,
      name: _initialName,
    );
  }

  Future<Object?> merge({
    String user = _person,
    _Origin origin = _Origin.manualLink,
  }) => _resolveMerge()(
    ownerId: _owner,
    phantomId: phantom,
    userId: user,
    origin: origin.code,
  );

  Future<String> createInvite() => getIt<PhantomCase>().saveInvite(
    ownerId: _owner,
    id: phantom,
    rotate: false,
  );

  Future<String> accept(String code, _Origin origin) async {
    if (origin == _Origin.inviteNew) {
      final result = await getIt<CredentialAuthCase>().resolveOrCreate(
        type: CredentialType.emailOtp,
        identifier: 'neighbour-$code@example.test',
        displayName: 'New Tentura account',
        inviteId: code,
      );
      expect(result.isNewAccount, isTrue);
      return result.accountId;
    }
    expect(
      await getIt<InvitationCase>().acceptAsExisting(
        code: code,
        userId: _person,
      ),
      InviteAcceptance.accepted,
    );
    return _person;
  }

  Future<void> pin(
    ConstellationAnchorTarget target,
    ConstellationAnchorPosition position,
  ) async {
    final result = await getIt<ScopedConstellationAnchorRepositoryPort>()
        .applyBatch(
          viewerId: _owner,
          ops: [
            AnchorApplyOp(
              clientOpId: 'pin-${_nextOperation++}',
              kind: AnchorOpKind.upsert,
              target: target,
              position: position,
            ),
          ],
        );
    expect(result.results.single.status, AnchorOpStatus.ok);
  }

  Future<String> tag(String name, List<String> members) async {
    final repository = getIt<PeopleTagsRepositoryPort>();
    final created = await repository.create(
      ownerId: _owner,
      clientOpId: 'create-${_nextOperation++}',
      fingerprint: name,
      name: name,
      glyph: 'T',
    );
    await repository.applyMembers(
      ownerId: _owner,
      clientOpId: 'members-${_nextOperation++}',
      fingerprint: name,
      ops: [
        for (final id in members)
          PersonTagMemberOp(
            tagId: created.id,
            personId: id,
            add: true,
            source: 0,
          ),
      ],
    );
    return created.id;
  }

  Future<void> saveContactName() => getIt<ContactCase>().set(
    viewerId: _owner,
    subjectId: _person,
    contactName: _savedName,
  );

  Future<String?> contactName(String user) => getIt<UserContactRepositoryPort>()
      .getName(viewerId: _owner, subjectId: user);

  Future<void> block(String blocker, String blocked) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
'''),
      parameters: {'blocker': blocker, 'blocked': blocked},
      timeout: kStableStateWait,
    );
  }

  Future<void> waitForMergeAuditWrite(
    int gatePid,
    Future<Object?> merge,
  ) async {
    var finished = false;
    final observed = merge.whenComplete(() => finished = true)..ignore();
    final clock = Stopwatch()..start();
    while (!finished && clock.elapsed < kStableStateWait) {
      final rows = await _sql(
        '''
SELECT EXISTS (
  SELECT 1 FROM pg_stat_activity
  WHERE datname = current_database() AND wait_event_type = 'Lock'
    AND @gatePid = ANY(pg_blocking_pids(pid))
)
''',
        {'gatePid': gatePid},
      );
      if (rows.single.single == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (finished) await observed;
    fail('The merge did not reach the held audit write.');
  }

  Future<bool> blockHides(String user) async =>
      (await _sql(
            'SELECT public.block_hides(@owner, @user)',
            {'owner': _owner, 'user': user},
          )).single.single!
          as bool;

  Future<void> makeInactive({String? previousUser}) async {
    await writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
UPDATE public.phantom
SET merged_at = now(), merged_user_id = @user::text, merge_origin = 3
WHERE id = @phantom
'''),
      parameters: {'phantom': phantom, 'user': previousUser},
    );
    expect((await phantomRow())['merged_at'], isNotNull);
  }

  Future<Map<String, Object?>> phantomRow() async => (await _rows(
    'SELECT * FROM public.phantom WHERE id = @id',
    {'id': phantom},
  )).single;

  Future<List<Map<String, Object?>>> mergeRows() => _rows(
    'SELECT * FROM public.phantom_merge WHERE phantom_id = @id ORDER BY id',
    {'id': phantom},
  );

  Future<Map<String, Object?>> undo() async {
    final rows = await mergeRows();
    expect(
      rows,
      hasLength(1),
      reason: 'The merge should commit one undo record.',
    );
    return _decodeUndo(rows.single);
  }

  Future<Map<String, Object?>> expectRecordedMerge(
    String user,
    _Origin origin,
    Map<String, Object?> before,
  ) async {
    final rows = await mergeRows();
    expect(
      rows,
      hasLength(1),
      reason: 'The merge should commit one audit row.',
    );
    final row = rows.single;
    expect(row['phantom_id'], phantom);
    expect(row['owner_id'], _owner);
    expect(row['user_id'], user);
    expect(row['origin'], origin.code);
    expect(row['undone_at'], isNull);
    final linked = await phantomRow();
    expect(linked['merged_user_id'], user);
    expect(linked['merged_at'], isA<DateTime>());
    expect(linked['merge_origin'], origin.code);
    expect(linked['current_merge_id'], row['id']);
    expect(linked['revision'], greaterThan(before['revision']! as int));
    return _decodeUndo(row);
  }

  Map<String, Object?> _decodeUndo(Map<String, Object?> merge) {
    final value = merge['undo'];
    return (value is String ? jsonDecode(value) : value)!
        as Map<String, Object?>;
  }

  Future<List<Map<String, Object?>>> pinRows() => _rows(
    '''
SELECT * FROM public.constellation_anchor WHERE viewer_id = @owner
ORDER BY target_kind, target_id
''',
    {'owner': _owner},
  );

  Future<Map<String, int>> watermarks() async => {
    for (final row in await _rows(
      '''
SELECT target_kind, revision
FROM public.constellation_anchor_target_watermark
WHERE viewer_id = @owner AND target_id IN (@person, @phantom)
''',
      {'owner': _owner, 'person': _person, 'phantom': phantom},
    ))
      row['target_kind']! as String: row['revision']! as int,
  };

  Future<List<Map<String, Object?>>> phantomMemberships() => _rows(
    '''
SELECT tag_id, owner_id, phantom_id, source, added_at, membership_id::text AS membership_id
FROM public.phantom_tag_member WHERE phantom_id = @id ORDER BY tag_id
''',
    {'id': phantom},
  );

  Future<List<Map<String, Object?>>> personMemberships() => _rows(
    '''
SELECT tag_id, owner_id, person_id, source, membership_id::text AS membership_id
FROM public.person_tag_member WHERE owner_id = @owner ORDER BY tag_id, person_id
''',
    {'owner': _owner},
  );

  Future<Map<String, List<String>>> visibleMemberships() async => {
    for (final row in await getIt<PeopleTagsRepositoryPort>().memberships(
      _owner,
    ))
      row.tagId: row.personIds,
  };

  Future<Map<String, int>> tagCounts() async => {
    for (final row in await getIt<PeopleTagsRepositoryPort>().list(_owner))
      row.id: row.count,
  };

  Future<List<Map<String, Object?>>> liveInvites() => _rows(
    '''
SELECT * FROM public.invitation
WHERE phantom_id = @id AND accepted_at IS NULL ORDER BY id
''',
    {'id': phantom},
  );

  Future<List<Map<String, Object?>>> inviteById(String code) => _rows(
    'SELECT id FROM public.invitation WHERE id = @code',
    {'code': code},
  );

  Future<List<Map<String, Object?>>> contactRows() => _rows(
    '''
SELECT * FROM public.user_contact WHERE viewer_id = @owner ORDER BY subject_id
''',
    {'owner': _owner},
  );

  Future<List<Map<String, Object?>>> mergeAttentionEvents() => _rows('''
SELECT occurrence.id AS occurrence_id,
       occurrence.immutable_payload ->> 'targetEntityId' AS target_id,
       recipient.account_id
FROM public.attention_occurrence occurrence
LEFT JOIN public.attention_occurrence_recipient recipient
  ON recipient.occurrence_id = occurrence.id
WHERE occurrence.event_type = 'phantomMerged'
ORDER BY occurrence.id, recipient.account_id
''');

  Future<Map<String, Object?>> guardSnapshot() async {
    final entry = await phantomRow();
    expect(entry, containsPair('current_merge_id', isNull));
    return {
      'merge records': await mergeRows(),
      'entry': entry,
      'pins': await pinRows(),
      'pin watermarks': await watermarks(),
      'original tag memberships': await phantomMemberships(),
      'account tag memberships': await personMemberships(),
      'live invites': await liveInvites(),
      'contact names': await contactRows(),
      'merge attention events': await mergeAttentionEvents(),
    };
  }
}

extension on _Fixture {
  Future<void> expectLinkedForUndo(
    _Origin origin, {
    String user = _person,
  }) async {
    final merge = (await mergeRows()).single;
    expect(
      await phantomRow(),
      allOf(
        containsPair('merged_user_id', user),
        containsPair('merged_at', isA<DateTime>()),
        containsPair('merge_origin', origin.code),
        containsPair('current_merge_id', merge['id']),
      ),
    );
    expect(merge['undone_at'], isNull);
  }

  Future<String> linkByAcceptedInvite({
    _Origin origin = _Origin.inviteExisting,
  }) async {
    final user = await accept(await createInvite(), origin);
    await getIt<PhantomMergeCase>().runDue(
      leaseOwner: 'unlink-test-worker',
      clock: () => DateTime.now().toUtc(),
    );
    await expectLinkedForUndo(origin, user: user);
    return user;
  }

  Future<void> editContactName(String name) => getIt<ContactCase>().set(
    viewerId: _owner,
    subjectId: _person,
    contactName: name,
  );

  Future<void> changeAccountMembership(String tag, {required bool add}) =>
      getIt<PeopleTagsRepositoryPort>().applyMembers(
        ownerId: _owner,
        clientOpId: 'members-${_nextOperation++}',
        fingerprint: '$tag-$add',
        ops: [
          PersonTagMemberOp(tagId: tag, personId: _person, add: add, source: 0),
        ],
      );

  Future<Map<(Object?, Object?), Map<String, Object?>>>
  livePinPositions() async => {
    for (final row in await pinRows())
      if (row['tombstone_at'] == null)
        (row['target_kind'], row['target_id']): {
          'xUnits': row['x_units'],
          'yUnits': row['y_units'],
          'coordinateSpaceVersion': row['coordinate_space_version'],
        },
  };

  Future<void> expectAdvancedWatermarks(Map<String, int> before) async {
    expect(await watermarks(), {
      'PERSON': greaterThan(before['PERSON']!),
      'PHANTOM': greaterThan(before['PHANTOM']!),
    });
  }

  Future<void> seedOutgoingVote() async {
    await _sql(
      '''
INSERT INTO public.vote_user (subject, object, amount)
VALUES (@owner, @person, 1)
''',
      {'owner': _owner, 'person': _person},
    );
  }

  Future<List<Map<String, Object?>>> pairVotes({String user = _person}) =>
      _rows(
        '''
SELECT * FROM public.vote_user
WHERE (subject = @owner AND object = @person)
   OR (subject = @person AND object = @owner)
ORDER BY subject
''',
        {'owner': _owner, 'person': user},
      );

  Future<List<List<Object?>>> projectedTrust(Session session) async => [
    for (final row in await session.execute(
      Sql.named('''
SELECT subject, object, trust_w, wall_d, target_w, prev_sent_weight
FROM public.user_trust_edge
WHERE (subject = @owner AND object = @person)
   OR (subject = @person AND object = @owner)
ORDER BY subject
'''),
      parameters: {'owner': _owner, 'person': _person},
    ))
      row.toList(),
  ];

  Future<List<List<Object?>>> projectionWithoutOutgoingVote() => writer.runTx((
    tx,
  ) async {
    const pair = {'owner': _owner, 'person': _person};
    await tx.execute(
      Sql.named(
        'DELETE FROM public.vote_user WHERE subject = @owner AND object = @person',
      ),
      parameters: pair,
    );
    await tx.execute(
      Sql.named('SELECT public.trust_project_pair(@owner, @person)'),
      parameters: pair,
    );
    final projection = await projectedTrust(tx);
    await tx.rollback();
    return projection;
  });

  Future<void> prepareInviteLinkWithTagsAndPin() async {
    final tagId = await tag('Neighbours', [phantom]);
    await pin(ConstellationAnchorPhantomTarget(phantom), _phantomPosition);
    await editContactName('Old');
    await linkByAcceptedInvite();
    final membership = (await personMemberships()).single;
    expect(
      membership,
      allOf(
        containsPair('tag_id', tagId),
        containsPair('person_id', _person),
      ),
    );
    expect((await undo())['insertedMembershipIds'], [
      membership['membership_id'],
    ]);
    expect(await livePinPositions(), {
      ('PERSON', _person): _phantomPosition.toFixtureMap(),
    });
    expect(await contactRows(), [
      allOf(
        containsPair('subject_id', _person),
        containsPair('contact_name', _initialName),
      ),
    ]);
    expect((await pairVotes()).map((row) => row['subject']), [_owner, _person]);
  }

  Future<Map<String, Object?>> unlinkSnapshot() async => {
    'entry': await phantomRow(),
    'merge records': await mergeRows(),
    'original tag memberships': await phantomMemberships(),
    'account tag memberships': await personMemberships(),
    'pins': await pinRows(),
    'pin watermarks': await watermarks(),
    'contact names': await contactRows(),
    'votes': await pairVotes(),
    'trust projection': await projectedTrust(writer),
    'live invites': await liveInvites(),
  };

  Future<void> seedActiveEntriesAtCap() async {
    await writer.executeWithOwnerScopes(
      [_owner],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
SELECT 'PHc' || lpad(to_hex(n), 11, '0'), @owner, 'Existing contact'
FROM generate_series(1, 200) AS n
'''),
      parameters: {'owner': _owner},
    );
  }

  Future<Object?> activeEntryCount() async => (await _sql(
    '''
SELECT count(*) FROM public.phantom WHERE owner_id = @owner AND merged_at IS NULL
''',
    {'owner': _owner},
  )).single.single;

  Future<void> eraseLinkedAccount() async {
    final deleted = await writer.runTx((tx) async {
      await tx.execute("SET LOCAL tentura.owner_scope_enforce = 'on'");
      return tx.execute(
        Sql.named('DELETE FROM public."user" WHERE id = @person RETURNING id'),
        parameters: {'person': _person},
      );
    });
    expect(deleted.single.single, _person);
  }
}
