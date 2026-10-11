// Plan D0: the real `PostBudRepository` over the real `RemoteApiService` and
// Ferry link chain. Pins the variables `PostBudFromPost` and
// `PostBudInviteCandidates` send, the mapping of their responses, and the
// typed exceptions for the bud error codes.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';

import '../../support/remote_wire_harness.dart';

const _postId = 'Bpost00000001';

Map<String, dynamic> _budResponse({
  String outcome = 'created',
  String? childBeaconId = 'Bchild0000001',
  List<Map<String, dynamic>> invitees = const [],
}) => {
  '__typename': 'mutation_root',
  'beaconBudFromPost': {
    '__typename': 'PostBudResult',
    'outcome': outcome,
    'childBeaconId': childBeaconId,
    'invitees': invitees,
  },
};

Map<String, dynamic> _invitee(String userId, String outcome) => {
  '__typename': 'PostBudInviteeResult',
  'userId': userId,
  'outcome': outcome,
};

Future<PostBudResult> _bud(PostBudRepository repo) => repo.budFromPost(
  postId: _postId,
  sourceMessageId: 'Mmsg00000001',
  clientCommandId: 'cmd-1',
  title: 'Fix the fence',
);

void main() {
  group('budFromPost', () {
    test('sends every argument and maps the result', () async {
      final sent = <WireSent>[];
      late PostBudResult result;
      await withRemoteWire(
        {
          'PostBudFromPost': _budResponse(
            invitees: [
              _invitee('Uinvitee00001', 'invited'),
              _invitee('Uinvitee00002', 'recipientPaused'),
              _invitee('Uinvitee00003', 'blocked'),
            ],
          ),
        },
        sent,
        (remote) async {
          result = await PostBudRepository(remote).budFromPost(
            postId: _postId,
            sourceMessageId: 'Mmsg00000001',
            clientCommandId: 'cmd-1',
            title: 'Fix the fence',
            description: 'Posts are loose',
            context: 'home',
            coordinates: const Coordinates(lat: 1.5, long: 2.5),
            startAt: DateTime.utc(2026, 10, 12, 9),
            endAt: DateTime.utc(2026, 10, 13, 18),
            tags: 'fence',
            needs: 'tools',
            primaryNeedSlug: 'tools',
            addressLabel: 'Garden',
            isDiscoverable: true,
            invitees: const [
              PostBudInvitee(userId: 'Uinvitee00001', note: 'You have a saw'),
              PostBudInvitee(userId: 'Uinvitee00002'),
            ],
            closePost: true,
          );
        },
      );

      expect(sent.single.operationName, 'PostBudFromPost');
      expect(sent.single.variables, {
        'postId': _postId,
        'sourceMessageId': 'Mmsg00000001',
        'clientCommandId': 'cmd-1',
        'title': 'Fix the fence',
        'description': 'Posts are loose',
        'context': 'home',
        'coordinates': {'lat': 1.5, 'long': 2.5},
        'startAt': '2026-10-12T09:00:00.000Z',
        'endAt': '2026-10-13T18:00:00.000Z',
        'tags': 'fence',
        'needs': 'tools',
        'primaryNeedSlug': 'tools',
        'addressLabel': 'Garden',
        'isDiscoverable': true,
        'invitees': [
          {'userId': 'Uinvitee00001', 'note': 'You have a saw'},
          {'userId': 'Uinvitee00002'},
        ],
        'closePost': true,
      });
      expect(result.outcome, PostBudOutcome.created);
      expect(result.childBeaconId, 'Bchild0000001');
      expect(result.invitees, const [
        PostBudInviteeResult(
          userId: 'Uinvitee00001',
          outcome: PostBudInviteOutcome.invited,
        ),
        PostBudInviteeResult(
          userId: 'Uinvitee00002',
          outcome: PostBudInviteOutcome.recipientPaused,
        ),
        PostBudInviteeResult(
          userId: 'Uinvitee00003',
          outcome: PostBudInviteOutcome.blocked,
        ),
      ]);
      expect(result.notInvitedUserIds, ['Uinvitee00002', 'Uinvitee00003']);
    });

    test('defaults: no invitees, not discoverable, Post stays open', () async {
      final sent = <WireSent>[];
      await withRemoteWire({'PostBudFromPost': _budResponse()}, sent, (
        remote,
      ) async {
        await _bud(PostBudRepository(remote));
      });
      final vars = sent.single.variables;
      expect(vars['isDiscoverable'], isFalse);
      expect(vars['closePost'], isFalse);
      expect(vars['invitees'], isEmpty);
      expect(vars['startAt'], isNull);
      expect(vars['endAt'], isNull);
    });

    test('maps an alreadyPromoted replay', () async {
      late PostBudResult result;
      await withRemoteWire(
        {
          'PostBudFromPost': _budResponse(
            outcome: 'alreadyPromoted',
            childBeaconId: 'Bexisting001',
          ),
        },
        <WireSent>[],
        (remote) async {
          result = await PostBudRepository(remote).budFromPost(
            postId: _postId,
            sourceMessageId: 'Mmsg00000001',
            clientCommandId: 'cmd-1',
            title: 'Fix the fence',
          );
        },
      );
      expect(result.outcome, PostBudOutcome.alreadyPromoted);
      expect(result.childBeaconId, 'Bexisting001');
      expect(result.invitees, isEmpty);
    });

    final errorCases = <int, Matcher>{
      1330: isA<PostChildRequiresBudException>(),
      1331: isA<BudSourceNotOwnMessageException>(),
      1332: isA<PostNotOpenException>(),
      1311: isA<BeaconPromotionSourceInvalidException>(),
    };
    for (final e in errorCases.entries) {
      test('error ${e.key} maps to its typed exception', () async {
        await withRemoteWire(
          const {},
          <WireSent>[],
          (remote) => expectLater(
            _bud(PostBudRepository(remote)),
            throwsA(e.value),
          ),
          errors: {'PostBudFromPost': wireCodeError(e.key)},
        );
      });
    }
  });

  group('inviteCandidates', () {
    test('sends postId and maps every candidate field in order', () async {
      final sent = <WireSent>[];
      late List<PostBudInviteCandidate> candidates;
      await withRemoteWire(
        {
          'PostBudInviteCandidates': {
            '__typename': 'query_root',
            'postBudInviteCandidates': [
              {
                '__typename': 'PostBudInviteCandidate',
                'userId': 'Uwriter000001',
                'warm': true,
                'outcome': 'invited',
                'pretick': true,
                'viaUserId': null,
                'hasWritten': true,
              },
              {
                '__typename': 'PostBudInviteCandidate',
                'userId': 'Ucold00000001',
                'warm': false,
                'outcome': 'alreadyInvited',
                'pretick': false,
                'viaUserId': 'Uvia000000001',
                'hasWritten': false,
              },
            ],
          },
        },
        sent,
        (remote) async {
          candidates = await PostBudRepository(
            remote,
          ).inviteCandidates(postId: _postId);
        },
      );

      expect(sent.single.operationName, 'PostBudInviteCandidates');
      expect(sent.single.variables, {'postId': _postId});
      expect(candidates, const [
        PostBudInviteCandidate(
          userId: 'Uwriter000001',
          warm: true,
          outcome: PostBudInviteOutcome.invited,
          pretick: true,
          hasWritten: true,
        ),
        PostBudInviteCandidate(
          userId: 'Ucold00000001',
          warm: false,
          outcome: PostBudInviteOutcome.alreadyInvited,
          pretick: false,
          hasWritten: false,
          viaUserId: 'Uvia000000001',
        ),
      ]);
      expect(candidates.first.isInvitable, isTrue);
      expect(candidates.last.isInvitable, isFalse);
    });

    test('a closed Post maps to PostNotOpenException', () async {
      await withRemoteWire(
        const {},
        <WireSent>[],
        (remote) => expectLater(
          PostBudRepository(remote).inviteCandidates(postId: _postId),
          throwsA(isA<PostNotOpenException>()),
        ),
        errors: {'PostBudInviteCandidates': wireCodeError(1332)},
      );
    });
  });
}
