import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_watch_grant_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/graph/data/repository/forwards_graph_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

enum GraphProjectionMode { meritRank, forwards, inviteGenealogy }

typedef GraphProjectionChange = ({
  RealtimeEntityKind? kind,
  String aggregateId,
});

sealed class GraphLoadRequest {
  const GraphLoadRequest();
}

final class MeritRankGraphLoad extends GraphLoadRequest {
  const MeritRankGraphLoad({
    required this.positiveOnly,
    required this.context,
    required this.focus,
    required this.limit,
    required this.viewerUserId,
  });

  final bool positiveOnly;
  final String context;
  final String? focus;
  final int limit;
  final String viewerUserId;
}

final class ForwardsGraphLoad extends GraphLoadRequest {
  const ForwardsGraphLoad({required this.beaconId, this.helpOffererId});

  final String beaconId;
  final String? helpOffererId;
}

final class GenealogyBootstrapGraphLoad extends GraphLoadRequest {
  const GenealogyBootstrapGraphLoad({this.targetId});

  final String? targetId;
}

final class GenealogyChildrenGraphLoad extends GraphLoadRequest {
  const GenealogyChildrenGraphLoad({
    required this.nodeKey,
    required this.limit,
    this.afterCreatedAt,
    this.afterNodeKey,
  });

  final String nodeKey;
  final int limit;
  final DateTime? afterCreatedAt;
  final String? afterNodeKey;
}

sealed class GraphLoadResult {
  const GraphLoadResult();
}

final class GraphEdgesResult extends GraphLoadResult {
  const GraphEdgesResult({
    required this.edges,
    this.helpOffererIds = const {},
    this.authorId = '',
    this.viewerId,
  });

  final Set<EdgeDirected> edges;
  final Set<String> helpOffererIds;
  final String authorId;
  final String? viewerId;
}

final class GenealogyBootstrapResult extends GraphLoadResult {
  const GenealogyBootstrapResult(this.graph);

  final InviteGenealogyGraph graph;
}

final class GenealogyChildrenResult extends GraphLoadResult {
  const GenealogyChildrenResult(this.page);

  final InviteGenealogyChildrenPage page;
}

final class GraphWatchProjection {
  const GraphWatchProjection({
    required this.focusId,
    required this.context,
    required this.positiveOnly,
    required this.userIds,
  });

  final String focusId;
  final String context;
  final bool positiveOnly;
  final Set<String> userIds;
}

/// Owns graph data-source selection, realtime routing, and bounded watches.
@injectable
final class GraphCase extends UseCaseBase {
  GraphCase(
    GraphRepository meritRank,
    ForwardsGraphRepository forwards,
    InviteGenealogyRepository genealogy,
    BeaconRepository beacons,
    ProfileRepositoryPort profiles,
    ContactsCase contacts,
    AuthCase auth,
    RealtimeSyncCase realtime,
    RealtimeWatchGrantPort watchGrants, {
    required Env env,
    required Logger logger,
  }) : this._(
         meritRank: meritRank,
         forwards: forwards,
         genealogy: genealogy,
         beacons: beacons,
         profiles: profiles,
         contacts: contacts,
         auth: auth,
         realtime: realtime,
         watchGrants: watchGrants,
         env: env,
         logger: logger,
       );

  @visibleForTesting
  GraphCase.forTesting({
    required Env env,
    required Logger logger,
    GraphSourceRepository? meritRank,
    ForwardsGraphRepository? forwards,
    InviteGenealogyRepository? genealogy,
    BeaconRepository? beacons,
    ProfileRepositoryPort? profiles,
    ContactsCase? contacts,
    AuthCase? auth,
    RealtimeSyncCase? realtime,
    RealtimeWatchGrantPort? watchGrants,
  }) : this._(
         meritRank: meritRank,
         forwards: forwards,
         genealogy: genealogy,
         beacons: beacons,
         profiles: profiles,
         contacts: contacts,
         auth: auth,
         realtime: realtime,
         watchGrants: watchGrants,
         env: env,
         logger: logger,
       );

  GraphCase._({
    required this._meritRank,
    required this._forwards,
    required this._genealogy,
    required this._beacons,
    required this._profiles,
    required this._contacts,
    required this._auth,
    required this._realtime,
    required this._watchGrants,
    required super.env,
    required super.logger,
  });

  final GraphSourceRepository? _meritRank;
  final ForwardsGraphRepository? _forwards;
  final InviteGenealogyRepository? _genealogy;
  final BeaconRepository? _beacons;
  final ProfileRepositoryPort? _profiles;
  final ContactsCase? _contacts;
  final AuthCase? _auth;
  final RealtimeSyncCase? _realtime;
  final RealtimeWatchGrantPort? _watchGrants;

  int _watchGeneration = 0;

  Stream<String> get accountChanges =>
      _auth?.currentAccountChanges() ?? const Stream.empty();

  Stream<GraphProjectionChange> projectionChanges({
    required GraphProjectionMode mode,
    String? beaconId,
  }) {
    final realtime = _realtime;
    if (realtime == null) return const Stream.empty();
    final entityKinds = <RealtimeEntityKind>{
      RealtimeEntityKind.relationship,
      RealtimeEntityKind.profile,
      if (mode == GraphProjectionMode.meritRank) RealtimeEntityKind.beacon,
      if (mode == GraphProjectionMode.forwards) ...{
        RealtimeEntityKind.beacon,
        RealtimeEntityKind.forward,
        RealtimeEntityKind.helpOffer,
      },
    };
    return MergeStream<GraphProjectionChange>([
      realtime
          .changesFor(entityKinds)
          .where((change) {
            if (mode != GraphProjectionMode.forwards) return true;
            return change.aggregateId == beaconId ||
                change.kind == RealtimeEntityKind.relationship ||
                change.kind == RealtimeEntityKind.profile;
          })
          .map(
            (change) => (kind: change.kind, aggregateId: change.aggregateId),
          ),
      realtime.catchUps.map((_) => (kind: null, aggregateId: '')),
      realtime.watchRefreshRequests
          .where((scope) => scope == RealtimeWatchScope.graph)
          .map((_) => (kind: null, aggregateId: '')),
      if (_contacts case final contacts?)
        contacts.changes.map(
          (_) => (
            kind: RealtimeEntityKind.contact,
            aggregateId: '',
          ),
        ),
    ]);
  }

  Future<GraphLoadResult> load(GraphLoadRequest request) async =>
      switch (request) {
        final MeritRankGraphLoad request => GraphEdgesResult(
          edges: await _requireMeritRank.fetch(
            positiveOnly: request.positiveOnly,
            context: request.context,
            focus: request.focus,
            limit: request.limit,
            viewerUserId: request.viewerUserId,
          ),
        ),
        final ForwardsGraphLoad request when request.helpOffererId != null =>
          _helpOffererResult(request),
        final ForwardsGraphLoad request => _forwardsResult(request),
        final GenealogyBootstrapGraphLoad request => GenealogyBootstrapResult(
          await _requireGenealogy.fetchGenealogyBootstrap(
            targetId: request.targetId,
          ),
        ),
        final GenealogyChildrenGraphLoad request => GenealogyChildrenResult(
          await _requireGenealogy.fetchChildren(
            nodeKey: request.nodeKey,
            afterCreatedAt: request.afterCreatedAt,
            afterNodeKey: request.afterNodeKey,
            limit: request.limit,
          ),
        ),
      };

  Future<Map<String, int>> fetchGenealogyChildCounts(
    Iterable<String> nodeKeys,
  ) {
    final keys = nodeKeys.where((key) => key.isNotEmpty).toSet();
    if (keys.isEmpty) return Future.value(const {});
    return _requireGenealogy.fetchChildCounts(nodeKeys: keys.toList());
  }

  Future<NodeDetails?> resolveNodeById(
    String id, {
    required int positionHint,
    bool pinned = false,
    Set<String> helpOffererIds = const {},
  }) async {
    if (id.startsWith('U')) {
      final profile = await _requireProfiles.fetchById(id);
      final contactName = _contacts?.nameOf(id);
      return UserNode(
        user: contactName == null || contactName.isEmpty
            ? profile.copyWith(contactName: '')
            : profile.copyWith(contactName: contactName),
        positionHint: positionHint,
        pinned: pinned,
        isHelpOfferer: helpOffererIds.contains(id),
      );
    }
    if (id.startsWith('B')) {
      try {
        return BeaconNode(
          beacon: await _requireBeacons.fetchBeaconById(id),
          positionHint: positionHint,
          pinned: pinned,
        );
      } on BeaconFetchException {
        return null;
      }
    }
    return null;
  }

  Future<void> replaceWatch(GraphWatchProjection projection) async {
    final realtime = _realtime;
    final grants = _watchGrants;
    if (realtime == null || grants == null) return;
    final generation = ++_watchGeneration;
    try {
      final grant = await grants.requestGrant(
        RealtimeWatchDescriptor.graph(
          requestedSubjectIds: projection.userIds,
          focusId: projection.focusId,
          context: projection.context,
          positiveOnly: projection.positiveOnly,
        ),
      );
      if (generation == _watchGeneration) realtime.replaceWatch(grant);
    } catch (error, stackTrace) {
      logger.warning('Graph realtime watch grant failed', error, stackTrace);
    }
  }

  void disposeProjection() {
    _watchGeneration++;
    _realtime?.removeWatch(RealtimeWatchScope.graph);
  }

  Future<GraphEdgesResult> _helpOffererResult(ForwardsGraphLoad request) async {
    final payload = await _requireForwards.fetchHelpOffererForwardsGraph(
      beaconId: request.beaconId,
      helpOffererId: request.helpOffererId!,
    );
    return GraphEdgesResult(
      edges: payload.edges,
      helpOffererIds: payload.helpOffererIds,
      authorId: payload.authorId,
      viewerId: payload.viewerId,
    );
  }

  Future<GraphEdgesResult> _forwardsResult(ForwardsGraphLoad request) async {
    final payload = await _requireForwards.fetchForwardsGraph(
      beaconId: request.beaconId,
    );
    return GraphEdgesResult(
      edges: payload.edges,
      helpOffererIds: payload.helpOffererIds,
      authorId: payload.authorId,
      viewerId: payload.viewerId,
    );
  }

  GraphSourceRepository get _requireMeritRank =>
      _meritRank ?? (throw StateError('MeritRank graph source is unavailable'));

  ForwardsGraphRepository get _requireForwards =>
      _forwards ?? (throw StateError('Forwards graph source is unavailable'));

  InviteGenealogyRepository get _requireGenealogy =>
      _genealogy ?? (throw StateError('Genealogy graph source is unavailable'));

  ProfileRepositoryPort get _requireProfiles =>
      _profiles ?? (throw StateError('Profile source is unavailable'));

  BeaconRepository get _requireBeacons =>
      _beacons ?? (throw StateError('Beacon source is unavailable'));
}
