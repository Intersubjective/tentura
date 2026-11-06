import 'package:freezed_annotation/freezed_annotation.dart';

import 'help_path_node.dart';
import 'forward_recipient_offer_status.dart';

part 'forward_graph.freezed.dart';

/// One forward edge as returned by the V2 `beaconForwardGraph` query.
@freezed
abstract class ForwardGraphEdge with _$ForwardGraphEdge {
  const factory ForwardGraphEdge({
    required String id,
    required String beaconId,
    required String senderId,
    required String recipientId,
    String? parentEdgeId,
    String? batchId,
    DateTime? createdAt,
    DateTime? readAt,
    bool? declinedInvite,
    bool? forwardedOn,
    ForwardRecipientOfferStatus? offerStatus,
    @Default(0) int senderAnonymousCount,
    @Default(0) int recipientAnonymousCount,
    String? senderDisplayName,
    String? recipientDisplayName,
  }) = _ForwardGraphEdge;

  const ForwardGraphEdge._();
}

/// Result payload for `ForwardRepository.fetchForwardGraph` and
/// `ForwardRepository.fetchHelpOffererForwardPath`. [viewerId] is non-null
/// only for the help-offerer-path query and is used to derive the viewer
/// role (author / help offerer / involved-other) when picking the AppBar
/// title and the focus node on the graph screen.
@freezed
abstract class ForwardGraph with _$ForwardGraph {
  const factory ForwardGraph({
    required String beaconId,
    required String authorId,
    @Default(<ForwardGraphEdge>[]) List<ForwardGraphEdge> edges,
    @Default(<String>{}) Set<String> helpOffererIds,
    String? viewerId,
    @Default(<HelpPathNode>[]) List<HelpPathNode> path,
  }) = _ForwardGraph;

  const ForwardGraph._();
}
