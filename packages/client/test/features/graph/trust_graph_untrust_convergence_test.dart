import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/graph/data/repository/graph_repository.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/like/domain/port/person_trust_writes_port.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_view_case.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/fake_person_shared_context_port.dart';
import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';

const _me = Profile(id: 'Uaaaaaaaaaaaa', displayName: 'Me');
const _bob = Profile(
  id: 'Ubbbbbbbbbbbb',
  displayName: 'Bob',
  myVote: 1,
  subjectExplicitlyTrustsViewer: true,
  isMutualFriend: true,
);
const _colors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

Future<void> main() async {
  group('Trust graph follows committed profile and remote untrust', () {
    test(
      'profile untrust alone removes the outgoing edge from an open graph',
      () async {
        await _withHarness((h) async {
          final result = await h.profileCase.removeFriend(_bob);
          h.expectProfileUntrustCommitted(result);

          expect(
            h.server.edges.map((edge) => (edge['src'], edge['dst'])).toSet(),
            {(_bob.id, _me.id)},
          );

          // No synthetic hint, catch-up, callback, navigation or graph patch.
          await h.waitForRealtimeWindow();

          h.expectOneWay(_bob.id, _me.id);
          expect(h.loadedBob.myVote, 0);
          expect(h.loadedBob.isMutualFriend, isFalse);
        });
      },
    );

    test(
      'profile untrust updates an open graph without a server echo even '
      'when the closure is already current',
      () async {
        await _withHarness((h) async {
          final result = await h.profileCase.removeFriend(_bob);
          h.expectProfileUntrustCommitted(result);

          final committedEdges = await h.graphSource.fetchEdgesBetween(
            nodeIds: {_me.id, _bob.id},
          );
          expect(
            committedEdges.map((edge) => (edge.src, edge.dst)).toSet(),
            {(_bob.id, _me.id)},
          );

          await h.waitForRealtimeWindow();

          h.expectOneWay(_bob.id, _me.id);
        });
      },
    );

    test(
      'remote untrust received over the websocket removes the incoming '
      'edge from the committed projection',
      () async {
        await _withHarness((h) async {
          h.server.remoteUntrust();
          h.receiveRemoteRelationshipFrame();

          await h.waitForRealtimeWindow();

          h.expectOneWay(_me.id, _bob.id);
          expect(h.loadedBob.subjectExplicitlyTrustsViewer, isFalse);
          expect(h.loadedBob.isMutualFriend, isFalse);
        });
      },
    );

    test(
      'remote websocket invalidation refreshes an already-current closure',
      () async {
        await _withHarness((h) async {
          h.server.remoteUntrust();
          h.receiveRemoteRelationshipFrame();

          await h.waitForRealtimeWindow();

          h.expectOneWay(_me.id, _bob.id);
          expect(h.loadedBob.subjectExplicitlyTrustsViewer, isFalse);
          expect(h.loadedBob.isMutualFriend, isFalse);
        });
      },
    );

    test(
      'reopening after profile untrust keeps the committed one-way '
      'relationship from the committed projection',
      () async {
        await _withHarness((h) async {
          final result = await h.profileCase.removeFriend(_bob);
          h.expectProfileUntrustCommitted(result);
          await h.graph.close();
          h.openGraph();
          await h.waitForGraphLoad();

          h.expectOneWay(_bob.id, _me.id);
          expect(h.loadedBob.myVote, 0);
          expect(h.loadedBob.isMutualFriend, isFalse);
        });
      },
    );

    test(
      'graph card untrust stays one-way across a websocket refresh',
      () async {
        await _withHarness((h) async {
          final fixture = GraphTrustWriteFixture(
            profileRepository: h.profiles,
            likeRepository: h.likes,
          );
          fixture.account.add(_me.id);
          try {
            final card = fixture.createCubit(
              viewerId: _me.id,
              profileViewCase: h.profileCase,
              onProfilePatched: h.graph.patchLoadedProfile,
            )..selectProfile(_bob, intentional: true);
            await pumpEventQueue(times: 10);
            await card.untrustSelected();
            await pumpEventQueue();
            expect(h.server.viewerTrustsBob, isFalse);
            h
              ..expectOneWay(_bob.id, _me.id)
              ..receiveRemoteRelationshipFrame();
            await h.waitForRealtimeWindow();

            h.expectOneWay(_bob.id, _me.id);
          } finally {
            await fixture.dispose();
          }
        });
      },
    );
  });
}

Future<void> _withHarness(
  Future<void> Function(_Harness) body, {
  _WireServer? serverOverride,
}) async {
  final server = serverOverride ?? _WireServer();
  await http.runWithClient(
    () async {
      final h = _Harness(server);
      try {
        await h.start();
        await body(h);
      } finally {
        await h.dispose();
      }
    },
    () => MockClient(server.handle),
  );
}

final class _Harness {
  _Harness(this.server);

  final _WireServer server;
  final socket = _Socket();
  final authLocal = StreamingAuthLocal();
  final contactStore = ContactNameStore();
  final effects = FakeUiEffectPort();
  late final RemoteApiService remote;
  late final InvalidationService invalidation;
  late final RealtimeSyncCase realtime;
  late final LikeRemoteRepository likes;
  late final ProfileRepository profiles;
  late final GraphRepository graphSource;
  late final ContactsCase contacts;
  late final ProfileViewCase profileCase;
  late GraphCubit graph;

  Future<void> start() async {
    remote = RemoteApiService(const Env(), _SocketFactory(socket));
    invalidation = InvalidationService(remote);
    realtime = RealtimeSyncCase(invalidation);
    likes = LikeRemoteRepository(
      remoteApiService: remote,
      log: Logger('likes'),
    );
    profiles = ProfileRepository(remote);
    graphSource = GraphRepository(
      remoteApiService: remote,
      log: Logger('graph'),
    );
    contacts = ContactsCase(
      FakeContactsRepository(),
      buildTestAuthCase(authLocal, EmptyAuthRemote()),
      contactStore,
      realtime,
      env: const Env(),
      logger: Logger('contacts'),
    );
    profileCase = ProfileViewCase(
      profiles,
      likes,
      _Capabilities(),
      contacts,
      realtime,
      FakePersonSharedContextPort(),
      env: const Env(),
      logger: Logger('profile'),
    );
    // Publish the same account-owned collaborators that production DI uses.
    GetIt.I.pushNewScope();
    GetIt.I
      ..registerSingleton<LikeRemoteRepository>(likes)
      ..registerSingleton<PersonTrustWritesPort>(likes)
      ..registerSingleton<ProfileRepositoryPort>(profiles)
      ..registerSingleton<RealtimeSyncCase>(realtime)
      ..registerSingleton<ProfileViewCase>(profileCase)
      ..registerSingleton<GraphRepository>(graphSource);
    await remote.setSessionAuth();
    await remote.bindRealtimeAccount(_me.id);
    socket.connections.add(RealtimeSocketConnectionState.connected);
    await pumpEventQueue();
    socket.frames.add(
      jsonEncode({
        'type': 'auth',
        'intent': 'sign_in',
        'result': 'success',
      }),
    );
    // Drain initial authentication/catch-up before opening the graph so it
    // cannot accidentally supply the local-write refresh under test.
    await waitForRealtimeWindow();
    openGraph();
    await waitForGraphLoad();
    expect(graph.viewerLink(_bob.id)?.fromViewer, greaterThan(0));
    expect(graph.viewerLink(_bob.id)?.toViewer, greaterThan(0));
  }

  void openGraph() {
    effects.clear();
    graph = GraphCubit(
      me: _me,
      graphSourceRepository: graphSource,
      edgeColors: _colors,
      beaconRepository: _UnusedBeaconRepository(),
      profileRepository: profiles,
      realtimeSyncCase: realtime,
      effects: effects,
    );
  }

  Future<void> waitForGraphLoad() async {
    if (graph.state.isLoading) {
      await graph.stream
          .firstWhere((state) => !state.isLoading)
          .timeout(
            const Duration(seconds: 30),
          );
    }
    expect(
      effects.emitted.whereType<ShowError>().map((effect) => effect.error),
      isEmpty,
      reason: 'the graph must load successfully before checking its edges',
    );
  }

  Profile get loadedBob =>
      (graph.graphController.nodes.singleWhere((n) => n.id == _bob.id)
              as UserNode)
          .user;

  void expectProfileUntrustCommitted(Profile result) {
    expect(server.voteWrites, [(personId: _bob.id, amount: 0)]);
    expect(server.viewerTrustsBob, isFalse);
    expect(result.myVote, 0);
    expect(result.isMutualFriend, isFalse);
    expect(server.profileReadsAfterVote, greaterThan(0));
  }

  void receiveRemoteRelationshipFrame() {
    // The server's entity_changes envelope enters at the socket, then crosses
    // RemoteApiClientWs -> InvalidationService -> RealtimeSyncCase -> graph.
    // The trigger coalesces the pair under its first sorted endpoint (Me),
    // rather than necessarily naming the person whose trust changed.
    socket.frames.add(
      jsonEncode({
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {
          'entity': 'relationship',
          'id': _me.id,
          'event': 'update',
          'actor_user_id': _bob.id,
        },
      }),
    );
  }

  Future<void> waitForRealtimeWindow() async {
    // Includes wire batching (100 ms) and the graph refresh debounce, inside
    // the documented connected-delivery budget (1.5 seconds).
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    await pumpEventQueue();
  }

  void expectOneWay(String src, String dst) {
    final link = graph.viewerLink(_bob.id);
    expect(link, isNotNull);
    expect(src == _me.id ? link!.fromViewer : link!.toViewer, greaterThan(0));
    expect(src == _me.id ? link.toViewer : link.fromViewer, isNull);
    final edge = graph.graphController.edges.singleWhere(
      (edge) =>
          {edge.source.id, edge.destination.id}.containsAll({_me.id, _bob.id}),
    );
    expect((edge.source.id, edge.destination.id), (src, dst));
    expect(edge.isReciprocal, isFalse);
    expect(edge.arrowAtSource, isFalse);
  }

  Future<void> dispose() async {
    await graph.close();
    await contacts.dispose();
    await invalidation.dispose();
    await likes.dispose();
    await profiles.dispose();
    await remote.close();
    await authLocal.dispose();
    await contactStore.dispose();
    await GetIt.I.popScope();
  }
}

/// HTTP is the only data seam: repositories, generated operation routing,
/// mutation responses and profile mapping remain production code.
final class _WireServer {
  bool viewerTrustsBob = true;
  bool bobTrustsViewer = true;
  int profileReadsAfterVote = 0;
  final voteWrites = <({String personId, int amount})>[];

  void remoteUntrust() => bobTrustsViewer = false;

  Map<String, Object?> user(String id) => {
    '__typename': 'user',
    'id': id,
    'display_name': id == _bob.id ? 'Bob' : 'Me',
    'description': '',
    'my_vote': id == _bob.id && viewerTrustsBob ? 1 : 0,
    'trusts_viewer': id == _bob.id && bobTrustsViewer,
    'is_mutual_friend': id == _bob.id && viewerTrustsBob && bobTrustsViewer,
    'image': null,
    'scores': <Object>[],
    'user_presence': null,
    'user_availability': null,
  };

  List<Map<String, Object?>> get edges => [
    if (viewerTrustsBob) edge(_me.id, _bob.id),
    if (bobTrustsViewer) edge(_bob.id, _me.id),
  ];

  Map<String, Object?> edge(String src, String dst) => {
    '__typename': 'graph_score',
    'src': src,
    'dst': dst,
    'src_score': 0.0,
    'dst_score': 1.0,
    'src_total_neighbor_count': 1,
    'dst_total_neighbor_count': 1,
    'user': user(dst),
  };

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _response({
        'subject': _me.id,
        'access_token': 'token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final variables = body['variables'] as Map<String, dynamic>;
    final Map<String, Object?> data;
    switch (body['operationName']) {
      case 'UserVote':
        expect(request.url.path, endsWith('/api/v2/graphql'));
        expect(variables['objectId'], _bob.id);
        final amount = variables['amount']! as int;
        voteWrites.add(
          (personId: variables['objectId']! as String, amount: amount),
        );
        viewerTrustsBob = amount > 0;
        data = {'userVote': amount};
      case 'UserFetchById':
        if (voteWrites.isNotEmpty) profileReadsAfterVote++;
        data = {'user_by_pk': user(variables['id']! as String)};
      case 'UsersFetchByIds':
        data = {
          'user': [
            for (final id in variables['ids']! as List) user(id as String),
          ],
        };
      case 'GraphFetch':
        data = {'graph': edges, 'beacon_by_pk': null};
      case 'GraphEdgesBetween':
        data = {'graph_edges_between': edges};
      default:
        throw StateError('Unexpected operation ${body['operationName']}');
    }
    return _response({'data': data});
  }

  http.Response _response(Map<String, Object?> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
}

final class _SocketFactory implements RealtimeSocketFactory {
  _SocketFactory(this.socket);
  final _Socket socket;
  @override
  RealtimeSocket create(Uri uri) => socket;
}

final class _Socket implements RealtimeSocket {
  final connections =
      StreamController<RealtimeSocketConnectionState>.broadcast();
  final frames = StreamController<Object?>.broadcast();
  @override
  Stream<RealtimeSocketConnectionState> get connection => connections.stream;
  @override
  Stream<Object?> get messages => frames.stream;
  @override
  void send(Object message) {}
  @override
  Future<void> close() async {
    await connections.close();
    await frames.close();
  }
}

final class _Capabilities implements CapabilityRepositoryPort {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      PersonCapabilityCues.empty;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _UnusedBeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
