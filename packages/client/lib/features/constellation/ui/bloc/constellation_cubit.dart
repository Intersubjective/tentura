import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/constellation_filters.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/use_case/constellation_field_case.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import 'constellation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'constellation_state.dart';

enum ConstellationEdgeKind {
  tier1Path,
  tier2Path,
  attachment,
  ringStub,
}

const kConstellationLayoutMaxHops = 3;

final class ConstellationCubit extends Cubit<ConstellationState> {
  ConstellationCubit({
    required ConstellationFieldCase case_,
    required Profile viewer,
    bool loadOnCreate = true,
  }) : _case = case_,
       _viewer = viewer,
       super(const ConstellationState()) {
    if (loadOnCreate) {
      unawaited(load());
    }
  }

  final ConstellationFieldCase _case;
  final Profile _viewer;

  final graphController =
      GraphController<NodeDetails, EdgeDetails<NodeDetails>>();

  final Map<String, ConstellationEdgeKind> edgeKinds = {};

  String layoutEgoId = '';
  Map<String, List<String>> layoutVisibleRequestsByAuthor = const {};
  Set<String> layoutEgoOwnRequestIds = const {};

  Future<void> load() async {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(status: StateIsLoading(), loadError: null));
    try {
      final resolved = await _case.load(viewerId: _viewer.id);
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: StateIsSuccess(),
          loadedAt: resolved.field.loadedAt,
          field: resolved.field,
          paths: resolved.paths,
          keptPeerIds: resolved.keptPeerIds,
          capped: resolved.capped,
          loadError: null,
        ),
      );
      _rebuildGraph();
    } on Object catch (error) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: StateIsSuccess(),
          loadError: error,
        ),
      );
    }
  }

  void selectRequest(String? requestId) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(selectedRequestId: requestId));
  }

  void _rebuildGraph() {
    final field = state.field;
    final paths = state.paths;
    if (field == null || paths == null) {
      graphController.clear();
      edgeKinds.clear();
      return;
    }

    final peersById = {for (final peer in field.peers) peer.id: peer};
    final visibleRequestIds = filterRequestIds(
      requests: field.requests.map(
        (request) => (
          id: request.id,
          needs: request.needs.toSet(),
          primaryNeedSlug: request.primaryNeedSlug,
          startAt: request.startAt,
          endAt: request.endAt,
          addressLabel: request.addressLabel,
          hasCoordinates: request.hasCoordinates,
        ),
      ),
      filters: state.filters,
      asOfUtc: DateTime.now().toUtc(),
    );

    final visibleRequests = [
      for (final request in field.requests)
        if (visibleRequestIds.contains(request.id)) request,
    ]..sort((a, b) => a.id.compareTo(b.id));

    final visibleRequestsByAuthor = <String, List<String>>{};
    final egoOwnRequestIds = <String>{};
    for (final request in visibleRequests) {
      visibleRequestsByAuthor
          .putIfAbsent(request.authorId, () => <String>[])
          .add(request.id);
      if (request.authorId == _viewer.id) {
        egoOwnRequestIds.add(request.id);
      }
    }
    for (final entry in visibleRequestsByAuthor.entries) {
      entry.value.sort();
    }

    layoutEgoId = _viewer.id;
    layoutVisibleRequestsByAuthor = visibleRequestsByAuthor;
    layoutEgoOwnRequestIds = egoOwnRequestIds;

    final nodes = <NodeDetails>{};
    final edges = <EdgeDetails<NodeDetails>>{};
    edgeKinds.clear();

    nodes.add(
      FieldPersonNode(
        person: _viewer,
        ring: 0,
        isKept: true,
      ),
    );

    final keptSorted = state.keptPeerIds.toList()..sort();
    for (final peerId in keptSorted) {
      final peer = peersById[peerId];
      if (peer == null) {
        continue;
      }
      final ring = paths.ring.contains(peerId)
          ? kConstellationLayoutMaxHops + 1
          : paths.depth[peerId] ?? kConstellationLayoutMaxHops;
      nodes.add(
        FieldPersonNode(
          person: _profileFromPeer(peer),
          ring: ring,
          isKept: paths.keep.contains(peerId),
        ),
      );
    }

    for (final request in visibleRequests) {
      nodes.add(FieldRequestNode(request: request));
    }

    final nodeById = {for (final node in nodes) node.id: node};

    void addEdge({
      required String srcId,
      required String dstId,
      required ConstellationEdgeKind kind,
    }) {
      final src = nodeById[srcId];
      final dst = nodeById[dstId];
      if (src == null || dst == null) {
        return;
      }
      final edge = EdgeDetails(
        source: src,
        destination: dst,
        color: Colors.transparent,
        strokeWidth: switch (kind) {
          ConstellationEdgeKind.tier1Path => 2,
          ConstellationEdgeKind.tier2Path => 2,
          ConstellationEdgeKind.attachment => 1.5,
          ConstellationEdgeKind.ringStub => 1.5,
        },
      );
      edges.add(edge);
      edgeKinds['$srcId\0$dstId'] = kind;
    }

    for (final child in paths.keep.intersection(state.keptPeerIds)) {
      final parentId = paths.parent[child];
      if (parentId == null) {
        continue;
      }
      final tier = paths.parentTier[child] ?? 1;
      addEdge(
        srcId: parentId,
        dstId: child,
        kind: tier == 1
            ? ConstellationEdgeKind.tier1Path
            : ConstellationEdgeKind.tier2Path,
      );
    }

    for (final ringPeer in paths.ring.intersection(state.keptPeerIds)) {
      addEdge(
        srcId: _viewer.id,
        dstId: ringPeer,
        kind: ConstellationEdgeKind.ringStub,
      );
    }

    for (final request in visibleRequests) {
      addEdge(
        srcId: request.authorId,
        dstId: request.id,
        kind: ConstellationEdgeKind.attachment,
      );
    }

    graphController.clear();
    graphController.mutate((mutator) {
      for (final node in nodes) {
        mutator.addNode(node);
      }
      for (final edge in edges) {
        mutator.addEdge(edge);
      }
    });
    emit(state.copyWith(graphRevision: state.graphRevision + 1));
  }

  Profile _profileFromPeer(ConstellationPerson peer) => Profile(
    id: peer.id,
    displayName: peer.displayName ?? '',
  );
}
