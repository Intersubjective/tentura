import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_member_webs_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_member_webs_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';

import '../../support/constellation_store_fixture.dart';

final class _StubRepository implements ConstellationRepositoryPort {
  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => ConstellationField(
    loadedAt: DateTime.utc(2026, 10, 7),
    context: '',
    // Visible peers remain on the Field independently of Request selection.
    // The member has no trust edges, holds no Request, and is not pinned.
    peers: const [
      ConstellationPerson(id: 'author'),
      ConstellationPerson(id: 'member'),
    ],
    edges: const [
      ConstellationTrustEdgeEntity(src: 'ego', dst: 'author', tier: 1),
    ],
    requests: const [
      ConstellationRequest(
        id: 'request',
        authorId: 'author',
        title: 'Need a ladder',
        status: 0,
      ),
      ConstellationRequest(
        id: 'other-request',
        authorId: 'author',
        title: 'Need a drill',
        status: 0,
      ),
    ],
  );
}

final class _StubMemberWebsPort implements ConstellationMemberWebsPort {
  @override
  Future<List<ConstellationMemberWeb>> fetch(String beaconId) async =>
      beaconId == 'request'
      ? const [
          ConstellationMemberWeb(
            beaconId: 'request',
            personId: 'member',
            state: ConstellationMemberWebState.inside,
          ),
        ]
      : const [];
}

Set<String> _graphNodeIds(ConstellationCubit cubit) =>
    cubit.graphController.nodes.map((node) => node.graphNodeId).toSet();

void _expectMemberSelected(ConstellationCubit cubit) {
  expect(cubit.state.selectedRequestId, isNull);
  expect(cubit.state.selectedPersonId, 'member');
  expect(cubit.state.composition!.eligiblePersonIds, contains('member'));
  expect(cubit.state.composition!.keptPeerIds, contains('member'));
  expect(_graphNodeIds(cubit), contains('fp:member'));
}

void _expectVisibleMember(ConstellationCubit cubit) {
  expect(cubit.state.composition!.eligiblePersonIds, contains('member'));
  expect(cubit.state.composition!.keptPeerIds, contains('member'));
  expect(_graphNodeIds(cubit), contains('fp:member'));
}

void main() {
  group('Request member person selection', () {
    late ConstellationCubit cubit;

    setUp(() async {
      cubit = ConstellationCubit(
        case_: ConstellationStoreFixture(
          _StubRepository(),
          accountId: 'ego',
        ).store,
        viewer: const Profile(id: 'ego', displayName: 'Ego'),
        memberWebsCase: ConstellationMemberWebsCase(
          _StubMemberWebsPort(),
          env: const Env(),
          logger: Logger('test'),
        ),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
      _expectVisibleMember(cubit);
      expect(cubit.state.paths!.keep, isNot(contains('member')));
      expect(cubit.state.paths!.ring, contains('member'));
      expect(cubit.state.field!.memberWebs, isEmpty);
      expect(
        cubit.state.field!.edges.where(
          (edge) => edge.src == 'member' || edge.dst == 'member',
        ),
        isEmpty,
      );

      final memberAdded = cubit.stream.firstWhere(
        (state) => state.composition!.eligiblePersonIds.contains('member'),
      );
      cubit.selectRequest('request');
      await memberAdded.timeout(const Duration(seconds: 2));
      expect(cubit.state.selectedRequestId, 'request');
      expect(cubit.state.selectedPersonId, isNull);
      expect(cubit.state.composition!.keptPeerIds, contains('member'));
      expect(cubit.state.paths!.ring, contains('member'));
      expect(_graphNodeIds(cubit), contains('fp:member'));
    });

    test(
      'keeps a visible member in composition and graph after deselection',
      () {
        cubit.selectPerson('member');
        _expectMemberSelected(cubit);

        cubit.selectPerson(null);
        expect(cubit.state.selectedPersonId, isNull);
        expect(cubit.state.selectedRequestId, isNull);
        _expectVisibleMember(cubit);
      },
    );

    test('keeps a visible member when another person is selected', () {
      cubit.selectPerson('member');
      _expectMemberSelected(cubit);

      cubit.selectPerson('author');
      expect(cubit.state.selectedPersonId, 'author');
      expect(cubit.state.selectedRequestId, isNull);
      expect(_graphNodeIds(cubit), contains('fp:author'));
      _expectVisibleMember(cubit);
    });

    test(
      'keeps a visible member when another Request is selected',
      () async {
        cubit.selectPerson('member');
        _expectMemberSelected(cubit);

        cubit.selectRequest('other-request');
        // Let the lazy member-web fetch for the new selection finish too.
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.selectedRequestId, 'other-request');
        expect(cubit.state.selectedPersonId, isNull);
        expect(_graphNodeIds(cubit), contains('fr:other-request'));
        _expectVisibleMember(cubit);
      },
    );
  });
}
