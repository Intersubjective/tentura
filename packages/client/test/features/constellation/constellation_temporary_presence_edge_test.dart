// A temporary person (visible only through one Request) is tied on the field
// to that Request by a dashed link, only with the field membership gate on and
// only while both nodes are on the field.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';

import '../../support/constellation_store_fixture.dart';

final _loadedAt = DateTime.utc(2026, 10, 25, 12);

final class _MutableRepository implements ConstellationRepositoryPort {
  _MutableRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

const _roofRequest = ConstellationRequest(
  id: 'B1',
  authorId: 'b',
  title: 'Fix the roof',
  status: 0,
);

/// Holds a Request of their own, so the person stays on the field whatever
/// the membership gate says; only the presence rendering is under test.
const _ownRequest = ConstellationRequest(
  id: 'req-t',
  authorId: 't',
  title: 'Seed tray',
  status: 0,
);

ConstellationPerson _person(
  ConstellationFieldMembership membership, {
  String? temporaryBeaconId = 'B1',
}) => ConstellationPerson(
  id: 't',
  displayName: 'Tia',
  fieldMembership: membership,
  temporaryBeaconId: temporaryBeaconId,
);

ConstellationField _field({
  ConstellationPerson? person,
  List<ConstellationRequest> requests = const [_roofRequest, _ownRequest],
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    const ConstellationPerson(id: 'b', displayName: 'Bea'),
    ?person,
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
    if (person != null)
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 't', tier: 1),
  ],
  requests: requests,
);

Future<ConstellationCubit> _load(
  ConstellationField field, {
  required bool gate,
  _MutableRepository? repository,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      repository ?? _MutableRepository(field),
      accountId: 'ego',
    ).store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    fieldMembershipV2Enabled: gate,
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

/// Endpoint ids (person and Request, in either direction) of every
/// temporary-presence link of the scene.
List<Set<String>> _links(ConstellationCubit cubit) => [
  for (final edge in cubit.graphController.edges)
    if (cubit.edgeKindByPair[edge.semanticId] ==
        ConstellationEdgeKind.temporaryPresence)
      {edge.source.id, edge.destination.id},
];

/// Records the `draw*` calls (name, arguments, paint at call time) the edge
/// painter issues, so the test sees what is actually stroked.
class _RecordingCanvas implements Canvas {
  final ops = <({String name, List<Object?> args, double strokeWidth})>[];

  Iterable<String> get names => ops.map((o) => o.name);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll(
      RegExp(r'Symbol\("|"\)'),
      '',
    );
    if (name.startsWith('draw')) {
      final args = invocation.positionalArguments;
      ops.add((
        name: name,
        args: args,
        strokeWidth: args.whereType<Paint>().first.strokeWidth,
      ));
    }
    return null;
  }
}

/// What the Field's own edge painter draws for [edge], 300 px long.
_RecordingCanvas _paintEdge(
  ConstellationCubit cubit,
  EdgeDetails edge,
) {
  final theme = TenturaTheme.light();
  final canvas = _RecordingCanvas();
  ConstellationEdgePainter(
    edgeKindByPair: cubit.edgeKindByPair,
    tt: theme.extension<TenturaTokens>()!,
    scheme: theme.colorScheme,
    repaint: ValueNotifier<int>(0),
    cameraScale: () => 1,
  ).paint(canvas, edge, Offset.zero, const Offset(300, 0));
  return canvas;
}

EdgeDetails _edgeOfKind(ConstellationCubit cubit, ConstellationEdgeKind kind) =>
    cubit.graphController.edges.firstWhere(
      (edge) => cubit.edgeKindByPair[edge.semanticId] == kind,
    );

void main() {
  group('temporary presence link painting', () {
    test(
      'is painted as dashes, thinner than a trust path, no end dots',
      () async {
        final cubit = await _load(
          _field(person: _person(ConstellationFieldMembership.temporary)),
          gate: true,
        );

        // The scene draws an edge out of the viewer only toward the selected
        // person, so one is selected to get a solid trust path to compare to.
        cubit.selectPerson('b');
        final path = _edgeOfKind(cubit, ConstellationEdgeKind.tier1Path);
        final solid = _paintEdge(cubit, path);
        expect(solid.names, [
          'drawLine',
        ], reason: 'positive control: a solid edge');

        final link = _paintEdge(
          cubit,
          _edgeOfKind(cubit, ConstellationEdgeKind.temporaryPresence),
        );
        expect(link.names, ['drawPath']);
        expect(
          link.ops.single.args.whereType<Path>().single.computeMetrics().length,
          greaterThan(5),
        );
        expect(
          link.ops.single.strokeWidth,
          lessThan(solid.ops.single.strokeWidth),
        );
      },
    );
  });

  group('temporary presence link', () {
    test('ties a temporary person to their Request with the gate on', () async {
      final cubit = await _load(
        _field(person: _person(ConstellationFieldMembership.temporary)),
        gate: true,
      );

      expect(cubit.requestById('B1'), isNotNull, reason: 'positive control');
      expect(_links(cubit), [
        {'t', 'B1'},
      ]);
    });

    test('is not drawn with the gate off', () async {
      final cubit = await _load(
        _field(person: _person(ConstellationFieldMembership.temporary)),
        gate: false,
      );

      expect(cubit.requestById('B1'), isNotNull, reason: 'positive control');
      expect(_links(cubit), isEmpty);
    });

    test('is not drawn when the Request is not on the field', () async {
      final cubit = await _load(
        _field(
          person: _person(ConstellationFieldMembership.temporary),
          requests: const [_ownRequest],
        ),
        gate: true,
      );

      expect(cubit.requestById('B1'), isNull);
      expect(_links(cubit), isEmpty);
    });

    test('is not drawn for a temporary person with no Request id', () async {
      final cubit = await _load(
        _field(
          person: _person(
            ConstellationFieldMembership.temporary,
            temporaryBeaconId: null,
          ),
        ),
        gate: true,
      );

      expect(_links(cubit), isEmpty);
    });

    for (final membership in [
      ConstellationFieldMembership.visible,
      ConstellationFieldMembership.bond,
    ]) {
      test('is not drawn for a ${membership.name} person', () async {
        final cubit = await _load(
          _field(person: _person(membership)),
          gate: true,
        );

        expect(cubit.requestById('B1'), isNotNull, reason: 'positive control');
        expect(_links(cubit), isEmpty);
      });
    }

    test('is gone when the person stays on the field but is no longer '
        'temporary', () async {
      final repository = _MutableRepository(
        _field(person: _person(ConstellationFieldMembership.temporary)),
      );
      final cubit = await _load(
        repository.field,
        gate: true,
        repository: repository,
      );
      expect(_links(cubit), hasLength(1), reason: 'positive control');

      repository.field = _field(
        person: _person(ConstellationFieldMembership.visible),
      );
      await cubit.load();

      expect(cubit.profileForPersonId('t'), isNotNull);
      expect(_links(cubit), isEmpty);
    });

    test('is gone after a field update without the person', () async {
      final repository = _MutableRepository(
        _field(person: _person(ConstellationFieldMembership.temporary)),
      );
      final cubit = await _load(
        repository.field,
        gate: true,
        repository: repository,
      );
      expect(_links(cubit), hasLength(1), reason: 'positive control');

      repository.field = _field(requests: const [_roofRequest]);
      await cubit.load();

      expect(cubit.profileForPersonId('t'), isNull);
      expect(_links(cubit), isEmpty);
    });
  });
}
