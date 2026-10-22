import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/invite_genealogy/data/repository/invite_genealogy_repository.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';

import '../../domain/port/home_inviter_port.dart';

/// Reads the viewer's direct inviter from their invite lineage (one edge per
/// descendant, so the viewer's own edge names the person who invited them).
@LazySingleton(
  as: HomeInviterPort,
  env: [Environment.dev, Environment.prod],
)
class HomeInviterRepository implements HomeInviterPort {
  HomeInviterRepository(this._genealogy);

  final InviteGenealogyRepository _genealogy;

  @override
  Future<Profile?> fetchMyInviter() async =>
      directInviterOf(await _genealogy.fetchGenealogyBootstrap());
}

/// The profile at the far end of the viewer's own lineage edge; null for a
/// root account, a deleted inviter, or an inviter without a readable profile.
@visibleForTesting
Profile? directInviterOf(InviteGenealogyGraph graph) {
  final viewer = graph.viewerNodeKey;
  if (viewer.isEmpty) return null;
  for (final edge in graph.edges) {
    if (edge.descendantNodeKey != viewer) continue;
    for (final node in graph.nodes) {
      if (node.nodeKey == edge.ancestorNodeKey) {
        return node.isDeleted ? null : node.profile;
      }
    }
    return null;
  }
  return null;
}
