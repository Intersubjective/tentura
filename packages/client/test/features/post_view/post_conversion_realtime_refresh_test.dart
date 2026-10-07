import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/domain/use_case/post_view_case.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _beaconId = 'Bconverted01';
const _author = Profile(id: 'Uauthorlive01', displayName: 'Author');
const _helper = Profile(id: 'Uhelperlive01', displayName: 'Helper');
const _forwardRecipient = Profile(
  id: 'Uforwardlive01',
  displayName: 'Recipient',
);
const _forwardSender = Profile(id: 'Urelaylive01', displayName: 'Morgan');

Beacon _post() => Beacon.empty.copyWith(
  id: _beaconId,
  author: _author,
  kind: BeaconKind.post,
  canReadContent: true,
);

Beacon _request() => _post().copyWith(
  kind: BeaconKind.request,
  title: 'Help move a piano',
  description: 'Third floor, no lift, Saturday.',
);

// Exercise the production mapping from a hint-only realtime event to a
// RepositoryEventInvalidate. Only the authoritative HTTP snapshot is a fake.
class _BeaconSnapshots extends BeaconRepository {
  _BeaconSnapshots(RemoteApiService remote, TestRealtimeSyncPort port)
    : super(remote, port);

  Beacon snapshot = _post();
  int fetchCount = 0;

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    expect(id, _beaconId);
    fetchCount++;
    return snapshot;
  }
}

class _PostSummaries implements PostsRepositoryPort {
  _PostSummaries(this.summary);

  final PostSummary summary;
  bool converted = false;

  @override
  Future<List<PostSummary>> myPosts() async => converted ? const [] : [summary];

  @override
  Future<PostSummary?> postSummary(String id) async =>
      (await myPosts()).firstOrNull;
}

class _Forwards implements ForwardRepository {
  _Forwards(this.edges);

  final List<ForwardEdge> edges;

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async {
    expect(beaconId, _beaconId);
    return edges;
  }

  @override
  Stream<String> get forwardChanges => const Stream.empty();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => const Stream.empty();

  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Open Post views follow conversion beacon hints', () {
    for (final (description, viewer) in [
      ('a carried-over helper', _helper),
      ('a forward-only recipient', _forwardRecipient),
      ('the author', _author),
    ]) {
      test(
        '$description sees the Request without reloading the Post',
        () async {
          final sync = buildTestRealtimeSync();
          addTearDown(sync.port.dispose);
          final remote = RemoteApiService(
            const Env.fromEnvironment(),
            const WebSocketClientRealtimeSocketFactory(),
          );
          addTearDown(remote.close);
          final repository = _BeaconSnapshots(remote, sync.port);
          addTearDown(repository.dispose);
          final isAuthor = viewer.id == _author.id;
          final isForwardOnly = viewer.id == _forwardRecipient.id;
          repository.snapshot = _post().copyWith(
            accessLevel: isAuthor
                ? BeaconAccessLevel.author
                : BeaconAccessLevel.member,
            accessReasons: isAuthor
                ? BeaconAccessReason.author.bit
                : BeaconAccessReason.forwarded.bit |
                      BeaconAccessReason.admitted.bit,
          );
          final receivedEdge = isAuthor
              ? null
              : ForwardEdge(
                  id: 'Freceivedlive01',
                  beaconId: _beaconId,
                  createdAt: DateTime.utc(2026, 10, 6),
                  sender: _forwardSender,
                  recipient: viewer,
                  note: 'I thought you could help with this',
                  context: 'neighbours',
                );
          // A newer edge for somebody else must not replace this viewer's
          // incoming provenance. After conversion the forward-only viewer has
          // no admitted participant or helper authority.
          final forwards = _Forwards([
            if (receivedEdge != null) receivedEdge,
            ForwardEdge(
              id: 'Fotherlive01',
              beaconId: _beaconId,
              createdAt: DateTime.utc(2026, 10, 7),
              sender: _forwardSender,
              recipient: const Profile(id: 'Uanotherlive01'),
            ),
          ]);
          final summaries = _PostSummaries(
            PostSummary(
              id: _beaconId,
              authorId: _author.id,
              authorName: _author.displayName,
              rootExcerpt: 'Anyone around on Saturday?',
              lastActivityAt: DateTime.utc(2026, 10, 6),
              isAuthor: isAuthor,
              unreadCount: isForwardOnly ? 2 : 0,
              lastMessageExcerpt: isForwardOnly
                  ? 'Morgan shared this Post'
                  : null,
            ),
          );
          final cubit = PostViewCubit(
            id: _beaconId,
            myProfile: viewer,
            beaconRepository: repository,
            postViewCase: PostViewCase(summaries, forwards),
            effects: FakeUiEffectPort(),
          );
          addTearDown(cubit.close);
          await cubit.fetch();
          expect(cubit.state.beacon.kind, BeaconKind.post);
          expect(cubit.state.summary, same(summaries.summary));
          expect(cubit.state.summary!.isAuthor, isAuthor);
          if (isForwardOnly) {
            expect(cubit.state.forwardedToMe, receivedEdge);
            expect(
              cubit.state.forwardedToMe!.recipient.id,
              _forwardRecipient.id,
            );
            expect(cubit.state.forwardedToMe!.sender.id, _forwardSender.id);
            expect(
              cubit.state.forwardedToMe!.note,
              'I thought you could help with this',
            );
            expect(cubit.state.summary!.unreadCount, 2);
          }
          final fetchesBefore = repository.fetchCount;

          repository.snapshot = _request().copyWith(
            accessLevel: isAuthor
                ? BeaconAccessLevel.author
                : isForwardOnly
                ? BeaconAccessLevel.observer
                : BeaconAccessLevel.member,
            accessReasons: isAuthor
                ? BeaconAccessReason.author.bit
                : isForwardOnly
                ? BeaconAccessReason.forwarded.bit
                : BeaconAccessReason.forwarded.bit |
                      BeaconAccessReason.admitted.bit,
            canReadInvolvement: !isForwardOnly,
            admittedHelperUsers: const [_helper],
            admittedHelperCount: 1,
          );
          if (isForwardOnly) {
            expect(repository.snapshot.accessLevel!.isMember, isFalse);
            expect(
              repository.snapshot.accessReasons,
              BeaconAccessReason.forwarded.bit,
            );
            expect(
              repository.snapshot.admittedHelperUsers,
              isNot(contains(viewer)),
            );
          }
          summaries.converted = true;
          // The server hint carries only an ID, never the converted entity.
          sync.port.emitChange(
            const RealtimeEntityChange(
              kind: RealtimeEntityKind.beacon,
              aggregateId: _beaconId,
              operation: RealtimeOperation.update,
              source: RealtimeChangeSource.serverInvalidation,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 400));

          expect(
            repository.fetchCount,
            greaterThan(fetchesBefore),
            reason: 'the conversion hint must refetch the open Post',
          );
          expect(cubit.state.beacon.kind, BeaconKind.request);
          expect(cubit.state.beacon.title, _request().title);
          expect(cubit.state.beacon.description, _request().description);
          if (isForwardOnly) {
            expect(cubit.state.beacon.accessLevel, BeaconAccessLevel.observer);
            expect(
              cubit.state.beacon.accessReasons,
              BeaconAccessReason.forwarded.bit,
            );
            expect(cubit.state.beacon.canReadInvolvement, isFalse);
            expect(cubit.state.forwardedToMe, receivedEdge);
          }
        },
      );
    }
  });
}
