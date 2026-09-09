import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

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

/// Server `HelpOfferCoordinationExceptionCode.offerKindChanged` wire code.
const kOfferKindChangedCoordinationCode = 1516;

enum ConstellationRequestPreflightOutcome {
  ready,
  authorizationDenied,
  requestUnavailable,
}

sealed class ConstellationRequestPreflight {
  const ConstellationRequestPreflight();

  const factory ConstellationRequestPreflight.ready({
    required Beacon beacon,
    required ConstellationRequest request,
    required bool viewerHasActiveHelpOffer,
  }) = ConstellationRequestPreflightReady;

  const factory ConstellationRequestPreflight.authorizationDenied({
    required String message,
  }) = ConstellationRequestPreflightAuthorizationDenied;

  const factory ConstellationRequestPreflight.requestUnavailable({
    required String message,
  }) = ConstellationRequestPreflightUnavailable;
}

final class ConstellationRequestPreflightReady extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightReady({
    required this.beacon,
    required this.request,
    required this.viewerHasActiveHelpOffer,
  });

  final Beacon beacon;
  final ConstellationRequest request;
  final bool viewerHasActiveHelpOffer;
}

final class ConstellationRequestPreflightAuthorizationDenied
    extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightAuthorizationDenied({
    required this.message,
  });

  final String message;
}

final class ConstellationRequestPreflightUnavailable
    extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightUnavailable({required this.message});

  final String message;
}

enum ConstellationOfferSubmitOutcome {
  success,
  offerKindChanged,
  validationFailed,
}

final class ConstellationCubit extends Cubit<ConstellationState> {
  ConstellationCubit({
    required ConstellationFieldCase case_,
    required Profile viewer,
    ForwardRepository? forwardRepository,
    bool loadOnCreate = true,
  }) : _case = case_,
       _viewer = viewer,
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       super(const ConstellationState()) {
    if (loadOnCreate) {
      unawaited(load());
    }
  }

  final ConstellationFieldCase _case;
  final Profile _viewer;
  final ForwardRepository _forwardRepository;

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

  String get viewerId => _viewer.id;

  Profile get viewer => _viewer;

  void selectRequest(String? requestId) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(selectedRequestId: requestId));
  }

  void setViewMode(ConstellationViewMode viewMode) {
    if (isClosed || state.viewMode == viewMode) {
      return;
    }
    emit(state.copyWith(viewMode: viewMode));
  }

  Future<ConstellationRequestPreflight> preflightRequestAction(
    String beaconId,
  ) async {
    try {
      final involvement = await _forwardRepository.fetchBeaconInvolvement(
        beaconId: beaconId,
      );
      final beacon = involvement.beacon;
      if (!beacon.status.isOpenFamily) {
        return ConstellationRequestPreflight.authorizationDenied(
          message: _authorizationDeniedMessage(beacon.status),
        );
      }
      final snapshot = requestById(beaconId);
      if (snapshot == null) {
        return const ConstellationRequestPreflight.requestUnavailable(
          message: 'This request is no longer in the field snapshot.',
        );
      }
      final viewerHasActiveHelpOffer =
          involvement.helpOfferedIds.contains(_viewer.id) &&
          !involvement.withdrawnIds.contains(_viewer.id);
      final viewerHasForwardEdge =
          involvement.myForwardedRecipientEdgeIds.isNotEmpty;
      final refreshed = _requestFromInvolvement(
        snapshot: snapshot,
        beacon: beacon,
        viewerHasActiveHelpOffer: viewerHasActiveHelpOffer,
        viewerHasForwardEdge: viewerHasForwardEdge,
      );
      _replaceRequestInField(refreshed);
      return ConstellationRequestPreflight.ready(
        beacon: beacon,
        request: refreshed,
        viewerHasActiveHelpOffer: viewerHasActiveHelpOffer,
      );
    } on BeaconFetchException {
      return const ConstellationRequestPreflight.requestUnavailable(
        message: 'This request is no longer available to you.',
      );
    } on Object catch (error) {
      if (_isAuthorizationFailure(error)) {
        return const ConstellationRequestPreflight.authorizationDenied(
          message: 'You can no longer act on this request.',
        );
      }
      return ConstellationRequestPreflight.requestUnavailable(
        message: error.toString(),
      );
    }
  }

  Future<ConstellationOfferSubmitOutcome> submitValidatedOfferHelp({
    required String beaconId,
    required int expectedOfferKind,
    required String message,
    List<String>? helpTypes,
  }) async {
    try {
      final ok = await _forwardRepository.offerHelp(
        beaconId: beaconId,
        message: message,
        helpTypes: helpTypes,
        expectedOfferKind: expectedOfferKind,
      );
      if (!ok) {
        return ConstellationOfferSubmitOutcome.validationFailed;
      }
      await preflightRequestAction(beaconId);
      return ConstellationOfferSubmitOutcome.success;
    } on Object catch (error) {
      if (_isOfferKindChanged(error)) {
        return ConstellationOfferSubmitOutcome.offerKindChanged;
      }
      return ConstellationOfferSubmitOutcome.validationFailed;
    }
  }

  int expectedOfferKindForRequest(ConstellationRequest request) {
    return BeaconStatus.fromSmallint(request.status) == BeaconStatus.enoughHelp
        ? 1
        : 0;
  }

  bool coverageRequiresExplicitBackupChoice({
    required ConstellationRequest snapshotRequest,
    required Beacon freshBeacon,
  }) {
    final snapshotOpen =
        BeaconStatus.fromSmallint(snapshotRequest.status) != BeaconStatus.enoughHelp;
    final freshCovered = freshBeacon.status == BeaconStatus.enoughHelp;
    return snapshotOpen && freshCovered;
  }

  void selectPerson(String? personId) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(selectedPersonId: personId));
  }

  void togglePersonRequestsExpanded(String personId) {
    if (isClosed) {
      return;
    }
    final expanded = Set<String>.from(state.expandedPersonIds);
    if (expanded.contains(personId)) {
      expanded.remove(personId);
    } else {
      expanded.add(personId);
    }
    emit(state.copyWith(expandedPersonIds: expanded));
  }

  ConstellationRequest? requestById(String requestId) {
    final field = state.field;
    if (field == null) {
      return null;
    }
    for (final request in field.requests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  Profile? profileForPersonId(String personId) {
    if (personId == _viewer.id) {
      return _viewer;
    }
    final field = state.field;
    if (field == null) {
      return null;
    }
    for (final peer in field.peers) {
      if (peer.id == personId) {
        return _profileFromPeer(peer);
      }
    }
    return null;
  }

  List<ConstellationRequest> discoverableRequestsForPerson(String personId) {
    final field = state.field;
    if (field == null) {
      return const [];
    }
    final visibleRequestIds = _visibleRequestIds(field);
    return [
      for (final request in field.requests)
        if (request.authorId == personId && visibleRequestIds.contains(request.id))
          request,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  Set<String> _visibleRequestIds(ConstellationField field) => filterRequestIds(
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

  void _rebuildGraph() {
    final field = state.field;
    final paths = state.paths;
    if (field == null || paths == null) {
      graphController.clear();
      edgeKinds.clear();
      return;
    }

    final peersById = {for (final peer in field.peers) peer.id: peer};
    final visibleRequestIds = _visibleRequestIds(field);

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
    handle: peer.handle ?? '',
    image: peer.image,
  );

  void _replaceRequestInField(ConstellationRequest refreshed) {
    final field = state.field;
    if (field == null) {
      return;
    }
    final requests = [
      for (final request in field.requests)
        if (request.id == refreshed.id) refreshed else request,
    ];
    emit(
      state.copyWith(
        field: field.copyWith(requests: requests),
      ),
    );
    _rebuildGraph();
  }

  ConstellationRequest _requestFromInvolvement({
    required ConstellationRequest snapshot,
    required Beacon beacon,
    required bool viewerHasActiveHelpOffer,
    required bool viewerHasForwardEdge,
  }) {
    return snapshot.copyWith(
      status: beacon.status.smallintValue,
      viewerHasActiveHelpOffer: viewerHasActiveHelpOffer,
      viewerHasForwardEdge: viewerHasForwardEdge,
    );
  }

  String _authorizationDeniedMessage(BeaconStatus status) => switch (status) {
    BeaconStatus.cancelled ||
    BeaconStatus.closed ||
    BeaconStatus.reviewOpen => 'This request is closed and no longer accepts help.',
    BeaconStatus.deleted => 'This request is no longer available.',
    BeaconStatus.draft => 'This request is not open yet.',
    _ => 'You can no longer act on this request.',
  };

  bool _isOfferKindChanged(Object error) {
    final code = _coordinationCodeFromError(error);
    return code == kOfferKindChangedCoordinationCode;
  }

  bool _isAuthorizationFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unauthorized') ||
        message.contains('cannot read request content');
  }

  int? _coordinationCodeFromError(Object error) {
    final text = error.toString();
    final match = RegExp(r'code\D*(\d{4})').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
