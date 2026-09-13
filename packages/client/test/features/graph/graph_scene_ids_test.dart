import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';

void main() {
  test('person and request with the same raw id get distinct graph node ids', () {
    const raw = 'shared-raw-key';
    final person = FieldPersonNode(
      person: Profile(id: raw),
      ring: 1,
      isKept: true,
    );
    final request = FieldRequestNode(
      request: ConstellationRequest(
        id: raw,
        authorId: 'author',
        title: 'Title',
        status: 0,
      ),
    );
    expect(tenturaGraphNodeId(person), isNot(tenturaGraphNodeId(request)));
    expect(tenturaLayoutDomainId(tenturaGraphNodeId(person)), raw);
    expect(tenturaLayoutDomainId(tenturaGraphNodeId(request)), raw);
  });

  test('genealogy nodes keep opaque nodeKey in graph id', () {
    const key = 'opaque-genealogy-key';
    final live = GenealogyUserNode(
      nodeKey: key,
      user: Profile(id: 'account-should-not-leak'),
    );
    expect(tenturaGraphNodeId(live), '${TenturaGraphNodeKind.genealogyUser}:$key');
    expect(tenturaLayoutDomainId(tenturaGraphNodeId(live)), key);
  });

  test('edge id ignores stroke style', () {
    final a = UserNode(user: Profile(id: 'a'));
    final b = UserNode(user: Profile(id: 'b'));
    final thin = EdgeDetails(
      source: a,
      destination: b,
      color: const Color(0xFF0000FF),
      strokeWidth: 2,
    );
    final thick = thin.copyWith(strokeWidth: 5);
    expect(tenturaGraphEdgeId(thin), tenturaGraphEdgeId(thick));
  });
}
