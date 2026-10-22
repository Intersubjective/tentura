import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/data/repository/home_inviter_repository.dart';
import 'package:tentura/features/home/domain/port/home_inviter_port.dart';
import 'package:tentura/features/home/ui/bloc/orientation_inviter_cubit.dart';
import 'package:tentura/features/invite_genealogy/domain/entity/invite_genealogy_graph.dart';

final _t = DateTime.utc(2026);

InviteGenealogyEdge _edge(String ancestor, String descendant) =>
    InviteGenealogyEdge(
      ancestorNodeKey: ancestor,
      descendantNodeKey: descendant,
      ancestorUserCreatedAt: _t,
      descendantUserCreatedAt: _t,
      createdAt: _t,
    );

class _FakePort implements HomeInviterPort {
  _FakePort(this.result);

  final Future<Profile?> Function() result;

  @override
  Future<Profile?> fetchMyInviter() => result();
}

void main() {
  group('directInviterOf (#523)', () {
    const root = Profile(id: 'U0', displayName: 'Root');
    const inviter = Profile(id: 'U1', displayName: 'Tab QA');

    test('picks the ancestor on the viewer own edge, not the root', () {
      final graph = InviteGenealogyGraph(
        viewerNodeKey: 'me',
        nodes: const [
          InviteGenealogyNode(nodeKey: 'root', profile: root),
          InviteGenealogyNode(nodeKey: 'inv', profile: inviter),
          InviteGenealogyNode(
            nodeKey: 'me',
            profile: Profile(id: 'U2'),
          ),
        ],
        edges: [_edge('root', 'inv'), _edge('inv', 'me')],
      );
      expect(directInviterOf(graph), inviter);
    });

    test('a root account has no inviter', () {
      const graph = InviteGenealogyGraph(
        viewerNodeKey: 'me',
        nodes: [],
        edges: [],
      );
      expect(directInviterOf(graph), isNull);
    });

    test('a deleted inviter is not named', () {
      final graph = InviteGenealogyGraph(
        viewerNodeKey: 'me',
        nodes: [
          InviteGenealogyNode(nodeKey: 'inv', profile: inviter, deletedAt: _t),
        ],
        edges: [_edge('inv', 'me')],
      );
      expect(directInviterOf(graph), isNull);
    });
  });

  group('OrientationInviterCubit', () {
    test('emits the inviter once known', () async {
      const inviter = Profile(id: 'U1', displayName: 'Tab QA');
      final cubit = OrientationInviterCubit(_FakePort(() async => inviter));
      addTearDown(cubit.close);
      expect(await cubit.stream.first, inviter);
    });

    test('stays null when the lookup fails', () async {
      final cubit = OrientationInviterCubit(
        _FakePort(() async => throw Exception('offline')),
      );
      addTearDown(cubit.close);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isNull);
    });
  });
}
