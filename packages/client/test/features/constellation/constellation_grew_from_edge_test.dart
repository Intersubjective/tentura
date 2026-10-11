// Plan D5: a Request budded from a Post is tied to it on the field by a
// `grewFrom` edge, drawn only when both the Post and the Request are nodes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_content.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';

final _loadedAt = DateTime.utc(2026, 10, 11, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

ConstellationRequest _child({String? parentBeaconId = 'post-1'}) =>
    ConstellationRequest(
      id: 'child-1',
      authorId: 'b',
      title: 'Move the piano',
      status: 0,
      parentBeaconId: parentBeaconId,
    );

ConstellationField _field({
  List<ConstellationRequest>? requests,
  bool withPost = true,
}) => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: [
    const ConstellationPerson(id: 'a'),
    const ConstellationPerson(id: 'b'),
  ],
  edges: [
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
    const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
  ],
  requests: requests ?? [_child()],
  posts: [
    if (withPost)
      ConstellationPost(
        id: 'post-1',
        authorId: 'a',
        rootExcerpt: 'Who has a van?',
        lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
      ),
  ],
);

Future<ConstellationCubit> _load(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

Iterable<String> _grewFromIds(ConstellationCubit cubit) => cubit
    .graphController
    .edges
    .map((e) => e.semanticId)
    .where((id) => id.endsWith('#grewFrom'));

void main() {
  group('scene', () {
    test('draws Post → child when both nodes are present', () async {
      final cubit = await _load(_field());
      addTearDown(cubit.close);

      expect(_grewFromIds(cubit), ['fr:post-1->fr:child-1#grewFrom']);
      expect(
        cubit.edgeKindByPair['fr:post-1->fr:child-1#grewFrom'],
        ConstellationEdgeKind.grewFrom,
      );
    });

    test('no edge when the Post is not on the field', () async {
      final cubit = await _load(_field(withPost: false));
      addTearDown(cubit.close);

      expect(cubit.requestById('child-1'), isNotNull);
      expect(_grewFromIds(cubit), isEmpty);
    });

    test('no edge when the child is not on the field', () async {
      final cubit = await _load(_field(requests: const []));
      addTearDown(cubit.close);

      expect(cubit.postById('post-1'), isNotNull);
      expect(_grewFromIds(cubit), isEmpty);
    });

    test('no edge for a Request without a readable Post parent', () async {
      final cubit = await _load(
        _field(requests: [_child(parentBeaconId: null)]),
      );
      addTearDown(cubit.close);

      expect(_grewFromIds(cubit), isEmpty);
    });
  });

  group('style', () {
    for (final theme in [TenturaTheme.light(), TenturaTheme.dark()]) {
      test('grewFrom has its own pattern (${theme.brightness.name})', () {
        final tt = theme.extension<TenturaTokens>()!;
        final scheme = theme.colorScheme;
        final grewFrom = constellationEdgeStyle(
          ConstellationEdgeKind.grewFrom,
          tt,
          scheme,
        );
        final others = {
          for (final kind in ConstellationEdgeKind.values)
            if (kind != ConstellationEdgeKind.grewFrom)
              constellationEdgeStyle(kind, tt, scheme),
        };
        expect(
          others.any(
            (o) =>
                (o.color, o.dash, o.gap, o.endDots) ==
                (grewFrom.color, grewFrom.dash, grewFrom.gap, grewFrom.endDots),
          ),
          isFalse,
          reason: 'a grewFrom edge must not read as another kind',
        );
        expect(grewFrom.dash, greaterThan(0), reason: 'non-color cue');
      });
    }

    testWidgets('the constellation legend names the grewFrom edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: GraphLegendContent(mode: GraphLegendMode.constellation),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Вырос из поста'), findsOneWidget);
    });
  });
}
