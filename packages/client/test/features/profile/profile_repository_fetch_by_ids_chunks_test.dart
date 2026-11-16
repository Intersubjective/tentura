import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import '../../support/remote_wire_harness.dart';
import '../../support/users_fetch_by_ids_wire.dart';

Set<String> _ids(int n) => {
  for (var i = 1; i <= n; i++) 'U${i.toString().padLeft(3, '0')}',
};

List<WireSent> _profileRequests(List<WireSent> sent) =>
    sent.where((r) => r.operationName == 'UsersFetchByIds').toList();

List<String> _idsOf(WireSent r) => (r.variables['ids'] as List).cast<String>();

void main() {
  group('ProfileRepository.fetchProfilesByIds with a capped user read', () {
    test('25 ids come back as 25 profiles in 3 requests of at most 10 ids, '
        'each id sent once', () async {
      final sent = <WireSent>[];
      final requested = _ids(25);
      late List<String> gotIds;
      late Map<String, String> names;
      await withCappedUsersWire(sent, (remote) async {
        final got = await ProfileRepository(
          remote,
        ).fetchProfilesByIds(requested).timeout(const Duration(seconds: 20));
        gotIds = [for (final p in got) p.id];
        names = {for (final p in got) p.id: p.displayName};
      });
      final reqs = _profileRequests(sent);
      expect(reqs, hasLength(3));
      for (final r in reqs) {
        expect(_idsOf(r).length, inInclusiveRange(1, 10));
      }
      final all = [for (final r in reqs) ..._idsOf(r)];
      expect(all, hasLength(25));
      expect(all.toSet(), requested);
      expect(gotIds.toSet(), requested);
      expect(gotIds, hasLength(25));
      expect(names['U017'], 'Name of U017');
    });

    test('exactly 10 ids need one request', () async {
      final sent = <WireSent>[];
      late int count;
      await withCappedUsersWire(sent, (remote) async {
        count =
            (await ProfileRepository(remote)
                    .fetchProfilesByIds(_ids(10))
                    .timeout(const Duration(seconds: 20)))
                .length;
      });
      final reqs = _profileRequests(sent);
      expect(reqs, hasLength(1));
      expect(_idsOf(reqs.single), hasLength(10));
      expect(count, 10);
    });

    test('11 ids need two requests (10 and 1)', () async {
      final sent = <WireSent>[];
      late int count;
      await withCappedUsersWire(sent, (remote) async {
        count =
            (await ProfileRepository(remote)
                    .fetchProfilesByIds(_ids(11))
                    .timeout(const Duration(seconds: 20)))
                .length;
      });
      final sizes = _profileRequests(sent).map((r) => _idsOf(r).length).toList()
        ..sort();
      expect(sizes, [1, 10]);
      expect(count, 11);
    });

    test('an empty id set makes no request', () async {
      final sent = <WireSent>[];
      late List<Object> got;
      await withCappedUsersWire(sent, (remote) async {
        got = await ProfileRepository(remote).fetchProfilesByIds(const {});
      });
      expect(got, isEmpty);
      expect(_profileRequests(sent), isEmpty);
    });

    test(
      'chunk requests are all in flight before any response is released',
      () async {
        final sent = <WireSent>[];
        final gate = Completer<void>();
        var arrived = 0;
        late int count;
        await withCappedUsersWire(
          sent,
          (remote) async {
            final future = ProfileRepository(
              remote,
            ).fetchProfilesByIds(_ids(25));
            // Poll until the transport has seen every chunk (or give up).
            for (var i = 0; i < 200 && _profileRequests(sent).length < 3; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            arrived = _profileRequests(sent).length;
            gate.complete();
            count = (await future.timeout(const Duration(seconds: 20))).length;
          },
          responseFor: (request) async {
            await gate.future;
            return cappedUsersAnswer(request);
          },
        );
        expect(arrived, 3);
        expect(count, 25);
      },
    );

    test('a profile returned in two chunk responses appears once', () async {
      final sent = <WireSent>[];
      final requested = _ids(25);
      late List<String> gotIds;
      var duplicated = 0;
      await withCappedUsersWire(
        sent,
        (remote) async {
          final got = await ProfileRepository(
            remote,
          ).fetchProfilesByIds(requested).timeout(const Duration(seconds: 20));
          gotIds = [for (final p in got) p.id];
        },
        responseFor: (request) async {
          final base = cappedUsersAnswer(request);
          // Re-serve U001 in every response that still has room under the
          // cap, so at least one other chunk repeats a row.
          final rows = (base['user'] as List).cast<Map<String, dynamic>>();
          if (rows.length < kWireUserRowCap &&
              !rows.any((r) => r['id'] == 'U001')) {
            rows.add(wireUserRow('U001'));
            duplicated++;
          }
          return base;
        },
      );
      expect(duplicated, greaterThan(0));
      expect(gotIds.where((id) => id == 'U001'), hasLength(1));
      expect(gotIds.toSet(), requested);
      expect(gotIds, hasLength(25));
    });
  });

  group('PostBudCase.inviteStep with a capped user read', () {
    test('12 candidates plus a via user all get a profile', () async {
      final sent = <WireSent>[];
      final candidates = [
        for (var i = 1; i <= 12; i++)
          {
            '__typename': 'PostBudInviteCandidate',
            'userId': 'Ucand${i.toString().padLeft(3, '0')}',
            'warm': true,
            'outcome': 'invited',
            'pretick': false,
            'viaUserId': i == 1 ? 'Uvia000000001' : null,
            'hasWritten': true,
          },
      ];
      late PostBudInviteStep step;
      await withCappedUsersWire(
        sent,
        (remote) async {
          final sut = PostBudCase(
            PostBudRepository(remote),
            ProfileRepository(remote),
            OpIdService(),
            env: const Env(),
            logger: Logger('invite-step-test'),
          );
          step = await sut
              .inviteStep('post-1')
              .timeout(
                const Duration(seconds: 20),
              );
        },
        responses: {
          'PostBudInviteCandidates': {
            '__typename': 'query_root',
            'postBudInviteCandidates': candidates,
          },
        },
      );
      expect(step.profiles.length, 13);
      expect(
        step.profiles.keys,
        containsAll([
          for (var i = 1; i <= 12; i++) 'Ucand${i.toString().padLeft(3, '0')}',
          'Uvia000000001',
        ]),
      );
    });
  });
}
