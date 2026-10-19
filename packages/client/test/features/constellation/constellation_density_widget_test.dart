import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_overflow_group.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

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

ConstellationFieldStoreCase _caseForField(ConstellationField field) =>
    ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store;

Future<ConstellationCubit> _loadCubit(
  ConstellationField field, {
  Size viewport = const Size(1200, 900),
  double textScale = 1.0,
}) async {
  final cubit = ConstellationCubit(
    case_: _caseForField(field),
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: viewport,
    textScaleFactor: textScale,
  );
  return cubit;
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required double width,
  required double textScale,
  List<Widget> extra = const [],
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TenturaResponsiveScope(
          child: BlocProvider<ConstellationCubit>.value(
            value: cubit,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConstellationFieldNotices(),
                  const ConstellationEmptyFilterBanner(),
                  const ConstellationFilterBar(),
                  ...extra,
                  _AbsenceProbeList(cubit: cubit),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _absenceLabel(L10n l10n, ConstellationCubit cubit, String personId) {
  final absence = cubit.absenceForPerson(personId);
  return switch (absence) {
    ConstellationNodeAbsence.none => '',
    ConstellationNodeAbsence.filterHidden =>
      l10n.constellationAbsenceFilterHidden,
    ConstellationNodeAbsence.spaceCollapsed =>
      l10n.constellationAbsenceSpaceCollapsed,
    ConstellationNodeAbsence.ring =>
      cubit.peersCapped
          ? l10n.constellationAbsencePathNotShown
          : l10n.constellationAbsenceRing,
    ConstellationNodeAbsence.capDisplaced =>
      l10n.constellationAbsenceCapDisplaced,
    ConstellationNodeAbsence.ringBudgetOmitted =>
      l10n.constellationAbsenceRingBudgetOmitted,
  };
}

String _requestAbsenceLabel(L10n l10n, ConstellationCubit cubit, String id) {
  return switch (cubit.absenceForRequest(id)) {
    ConstellationNodeAbsence.none => '',
    ConstellationNodeAbsence.filterHidden =>
      l10n.constellationAbsenceFilterHidden,
    ConstellationNodeAbsence.spaceCollapsed =>
      l10n.constellationAbsenceSpaceCollapsed,
    _ => '',
  };
}

Map<String, Offset> _personPositions(ConstellationCubit cubit) {
  final resolved = cubit.state.resolvedField;
  if (resolved == null) {
    return const {};
  }
  final layout = computeConstellationLayout(
    egoId: cubit.viewerId,
    paths: resolved.paths,
    keptPeerIds: resolved.keptPeerIds,
    visibleRequestsByAuthor: cubit.layoutVisibleRequestsByAuthor,
    egoOwnRequestIds: cubit.layoutEgoOwnRequestIds,
  );
  return {
    for (final entry in layout.positions.entries)
      if (!entry.key.startsWith('req-'))
        entry.key: Offset(entry.value.x, entry.value.y),
  };
}

ConstellationField _baseField({
  bool peersCapped = false,
  bool requestsCapped = false,
  List<ConstellationRequest> requests = const [],
  List<ConstellationPerson> peers = const [],
  List<ConstellationTrustEdgeEntity> edges = const [],
}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peers: peers,
    edges: edges,
    requests: requests,
    peersCapped: peersCapped,
    requestsCapped: requestsCapped,
  );
}

class _AbsenceProbeList extends StatelessWidget {
  const _AbsenceProbeList({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final probes = <Widget>[];
    final field = cubit.state.field;
    if (field != null) {
      for (final peer in field.peers) {
        final label = _absenceLabel(l10n, cubit, peer.id);
        if (label.isNotEmpty) {
          probes.add(Text(label, key: Key('absence.person.${peer.id}')));
        }
      }
      for (final request in field.requests) {
        final label = _requestAbsenceLabel(l10n, cubit, request.id);
        if (label.isNotEmpty) {
          probes.add(Text(label, key: Key('absence.request.${request.id}')));
        }
      }
    }
    return Column(children: probes);
  }
}

void main() {
  group('Constellation density and filter widgets', () {
    testWidgets(
      'filter sections: label gap is rowGap, chips in the Wrap',
      (
        tester,
      ) async {
        final cubit = await _loadCubit(
          _baseField(
            peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
            edges: [
              const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            ],
            requests: [
              const ConstellationRequest(
                id: 'req-a',
                authorId: 'a',
                title: 'Need tools',
                status: 0,
                needs: ['tools'],
              ),
            ],
          ),
        );
        await _pumpHarness(tester, cubit: cubit, width: 390, textScale: 1);
        final context = tester.element(
          find.byKey(const Key('constellation.filter_bar')),
        );
        final rowGap = context.tt.rowGap;
        final l10n = L10n.of(context)!;

        // Capability chips are grouped by the Requirements taxonomy (#457),
        // so "Any" and "tools" need not share one Wrap; grouping is pinned
        // by its own test below.
        for (final (label, firstChip, otherChip) in [
          (
            l10n.constellationFilterCapability,
            'constellation.filter.capability.any',
            'constellation.filter.capability.any',
          ),
          (
            l10n.constellationFilterLocation,
            'constellation.filter.location.any',
            'constellation.filter.location.unspecified',
          ),
          (
            l10n.constellationFilterTiming,
            'constellation.filter.timing.any',
            'constellation.filter.timing.undated',
          ),
        ]) {
          final labelRect = tester.getRect(find.text(label));
          final wrap = find.ancestor(
            of: find.byKey(Key(firstChip)),
            matching: find.byType(Wrap),
          );
          expect(
            tester.getTopLeft(wrap.first).dy - labelRect.bottom,
            closeTo(rowGap, 0.5),
            reason: label,
          );
          expect(
            find.descendant(
              of: wrap.first,
              matching: find.byKey(Key(otherChip)),
            ),
            findsOneWidget,
            reason: label,
          );
        }
      },
    );

    // #457: the capability chip that clears the filter was labelled
    // "Unspecified" beside a separate "Include unspecified" switch, and the
    // sheet ended in a developer note.
    testWidgets('capability filters start with Any; no developer note', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      );
      await _pumpHarness(tester, cubit: cubit, width: 390, textScale: 1);

      final any = find.byKey(const Key('constellation.filter.capability.any'));
      expect(
        find.descendant(of: any, matching: find.text('Any')),
        findsOneWidget,
      );
      final chips = tester
          .widget<Wrap>(
            find.ancestor(of: any, matching: find.byType(Wrap)).first,
          )
          .children;
      expect(chips.first.key, const Key('constellation.filter.capability.any'));
      expect(
        find.byKey(const Key('constellation.filter.limitations')),
        findsNothing,
      );
    });

    // #457 (Vadim, Oct 18): the capability chips use the same taxonomy as
    // the Requirements picker in the request editor, grouped the same way
    // (Logistics, Communication, Knowledge, Care, Resources, Technical...),
    // not one flat list sorted by slug.
    testWidgets('capability chips are grouped like the Requirements picker', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-sw',
              authorId: 'a',
              title: 'Need code',
              status: 0,
              needs: ['software'],
            ),
            const ConstellationRequest(
              id: 'req-pets',
              authorId: 'a',
              title: 'Need a dog sitter',
              status: 0,
              needs: ['pets'],
            ),
            const ConstellationRequest(
              id: 'req-move',
              authorId: 'a',
              title: 'Need a van and a drill',
              status: 0,
              needs: ['transport', 'tools'],
            ),
          ],
        ),
      );
      await _pumpHarness(tester, cubit: cubit, width: 390, textScale: 1);
      final bar = find.byKey(const Key('constellation.filter_bar'));
      final l10n = L10n.of(tester.element(bar))!;

      Finder inBar(Finder f) => find.descendant(of: bar, matching: f);
      double top(Finder f) => tester.getTopLeft(f).dy;

      final logistics = inBar(find.text(l10n.capabilityGroupLogistics));
      final care = inBar(find.text(l10n.capabilityGroupCare));
      final technical = inBar(find.text(l10n.capabilityGroupTechnical));
      expect(logistics, findsOneWidget);
      expect(care, findsOneWidget);
      expect(technical, findsOneWidget);

      // Only groups that have a capability in the field get a header; the
      // filter does not dump the whole catalog.
      expect(
        inBar(find.text(l10n.capabilityGroupCommunication)),
        findsNothing,
      );
      expect(inBar(find.text(l10n.capabilityGroupRpg)), findsNothing);
      expect(
        find.byKey(const Key('constellation.filter.capability.calls')),
        findsNothing,
      );

      // Every available chip is visible without opening anything.
      Finder chip(String slug) =>
          find.byKey(Key('constellation.filter.capability.$slug'));
      for (final slug in ['transport', 'tools', 'pets', 'software']) {
        expect(chip(slug), findsOneWidget, reason: slug);
      }
      expect(
        find.byKey(const Key('constellation.filter.capability.any')),
        findsOneWidget,
      );

      // Taxonomy order (CapabilityGroup), each chip under its own header.
      expect(top(logistics), lessThan(top(chip('transport'))));
      expect(top(logistics), lessThan(top(chip('tools'))));
      expect(top(chip('transport')), lessThan(top(care)));
      expect(top(chip('tools')), lessThan(top(care)));
      expect(top(care), lessThan(top(chip('pets'))));
      expect(top(chip('pets')), lessThan(top(technical)));
      expect(top(technical), lessThan(top(chip('software'))));
      // The capability section still sits above Location.
      expect(
        top(chip('software')),
        lessThan(
          top(find.byKey(const Key('constellation.filter.location.any'))),
        ),
      );

      // Grouped chips still filter.
      await tester.ensureVisible(chip('pets'));
      await tester.pumpAndSettle();
      await tester.tap(chip('pets'));
      await tester.pumpAndSettle();
      expect(cubit.state.filterCapabilitySlugs, {'pets'});
    });

    // #457 (Vadim, Oct 18): one clearly named switch, "Include requests
    // without a capability", instead of the generic "Include unspecified"
    // that sat beside the Location and Timing "Unspecified" chips.
    testWidgets('include switch names both things it governs', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      );
      await _pumpHarness(tester, cubit: cubit, width: 390, textScale: 1);
      final toggle = find.byKey(
        const Key('constellation.filter.include_unspecified'),
      );
      expect(toggle, findsOneWidget);
      // The switch lets through requests without a capability AND undated
      // requests under "within N days", so the label must name both.
      final enTitle = tester.widget<Text>(
        find.descendant(of: toggle, matching: find.byType(Text)).first,
      );
      expect(enTitle.data, isNot('Include unspecified'));
      expect(
        enTitle.data,
        allOf(contains('without a capability'), contains('date')),
      );
      expect(find.text('Include unspecified'), findsNothing);
      // Russian: the same meaning, not the old «Включать не указанные».
      await _pumpHarness(
        tester,
        cubit: cubit,
        width: 390,
        textScale: 1,
        locale: const Locale('ru'),
      );
      final ruTitle = tester.widget<Text>(
        find.descendant(of: toggle, matching: find.byType(Text)).first,
      );
      expect(ruTitle.data, isNot('Включать не указанные'));
      expect(ruTitle.data, allOf(contains('без навык'), contains('дат')));
    });

    testWidgets(
      'compact and expanded layouts keep controls readable at text scales',
      (tester) async {
        for (final width in [390.0, 900.0]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            final cubit = await _loadCubit(
              _baseField(
                peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
                edges: [
                  const ConstellationTrustEdgeEntity(
                    src: 'ego',
                    dst: 'a',
                    tier: 1,
                  ),
                ],
                requests: [
                  const ConstellationRequest(
                    id: 'req-a',
                    authorId: 'a',
                    title: 'Need tools',
                    status: 0,
                    needs: ['tools'],
                  ),
                ],
              ),
              viewport: Size(width, 800),
              textScale: scale,
            );
            await _pumpHarness(
              tester,
              cubit: cubit,
              width: width,
              textScale: scale,
            );

            final filterBar = tester.getSize(
              find.byKey(const Key('constellation.filter_bar')),
            );
            expect(filterBar.width, greaterThan(0));
            expect(filterBar.height, greaterThan(44 * scale));

            final chip = tester.getSize(
              find.byKey(const Key('constellation.filter.location.any')),
            );
            expect(chip.height, greaterThanOrEqualTo(44));
          }
        }
      },
    );

    testWidgets('changing filters does not move person anchors', (
      tester,
    ) async {
      final field = _baseField(
        peers: [
          const ConstellationPerson(id: 'a'),
          const ConstellationPerson(id: 'b'),
        ],
        edges: [
          const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          const ConstellationTrustEdgeEntity(src: 'ego', dst: 'b', tier: 1),
        ],
        requests: [
          const ConstellationRequest(
            id: 'req-a',
            authorId: 'a',
            title: 'Tools',
            status: 0,
            needs: ['tools'],
          ),
          const ConstellationRequest(
            id: 'req-b',
            authorId: 'b',
            title: 'Ride',
            status: 0,
            needs: ['ride'],
          ),
        ],
      );
      final cubit = await _loadCubit(field);
      final before = _personPositions(cubit);

      cubit.setFilterCapabilitySlugs({'tools'});
      final filtered = _personPositions(cubit);
      expect(filtered['a'], before['a']);
      expect(filtered['b'], before['b']);

      cubit.clearFilters();
      final restored = _personPositions(cubit);
      expect(restored['a'], before['a']);
      expect(restored['b'], before['b']);
    });

    testWidgets('four per-node absence states render distinctly', (
      tester,
    ) async {
      final prolific = List.generate(
        6,
        (i) => ConstellationRequest(
          id: 'req-p$i',
          authorId: 'p',
          title: 'Need $i',
          status: 0,
          needs: ['tools'],
        ),
      );
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'p'),
            const ConstellationPerson(id: 'r'),
            const ConstellationPerson(id: 'd'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'p', tier: 1),
          ],
          requests: [
            ...prolific,
            const ConstellationRequest(
              id: 'req-hidden',
              authorId: 'p',
              title: 'Hidden ride',
              status: 0,
              needs: ['ride'],
            ),
            const ConstellationRequest(
              id: 'req-r',
              authorId: 'r',
              title: 'Ring',
              status: 0,
            ),
          ],
        ),
        viewport: const Size(400, 400),
        textScale: 1.0,
      );

      cubit.setFilterCapabilitySlugs({'tools'});
      cubit.droppedHolderIds = {'d'};
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 400, textScale: 1.0);

      expect(
        find.text('Hidden by your filters'),
        findsOneWidget,
      );
      expect(find.text('Collapsed to save space'), findsWidgets);
      expect(
        find.text("Connection not explained within this map's path rules"),
        findsOneWidget,
      );
      expect(
        find.text("Known connection omitted by the map's render budget"),
        findsOneWidget,
      );
    });

    testWidgets('peersCapped alone shows path notice and fallback link', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peersCapped: true,
          peers: [
            const ConstellationPerson(id: 'r'),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-ego',
              authorId: 'ego',
              title: 'My need',
              status: 0,
              isMine: true,
            ),
            const ConstellationRequest(
              id: 'req-r',
              authorId: 'r',
              title: 'Ring need',
              status: 0,
            ),
          ],
        ),
      );

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some connection paths are not shown'),
        findsOneWidget,
      );
      expect(find.textContaining('field too large'), findsNothing);
      expect(find.textContaining('requests are hidden'), findsNothing);
      expect(
        find.byKey(const Key('constellation.notice.fallback_list')),
        findsOneWidget,
      );
      expect(cubit.displayedRequestIds, contains('req-ego'));
      expect(
        find.text('Path not shown'),
        findsOneWidget,
      );
      expect(
        find.text("Connection not explained within this map's path rules"),
        findsNothing,
      );
      expect(
        find.byKey(const Key('constellation.notice.requests_capped')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('constellation.notice.render_budget_capped')),
        findsNothing,
      );
    });

    testWidgets(
      'requestsCapped alone shows distinct copy without path notice',
      (
        tester,
      ) async {
        final cubit = await _loadCubit(
          _baseField(requestsCapped: true),
        );
        await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

        expect(find.text('Some requests could not be loaded'), findsOneWidget);
        expect(
          find.text('Some connection paths are not shown'),
          findsNothing,
        );
      },
    );

    testWidgets('client render budget capped alone shows budget notice', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
            const ConstellationPerson(id: 'h'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'b', dst: 'h', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-h',
              authorId: 'h',
              title: 'Deep',
              status: 0,
            ),
          ],
        ),
      );
      cubit.droppedHolderIds = {'h'};
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some people were omitted to keep the map readable'),
        findsOneWidget,
      );
      expect(
        find.text('Some connection paths are not shown'),
        findsNothing,
      );
      expect(
        find.text("Known connection omitted by the map's render budget"),
        findsOneWidget,
      );
    });

    testWidgets('ring-only budget omission stays ring classification', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peers: [
            const ConstellationPerson(id: 'a'),
            const ConstellationPerson(id: 'b'),
            const ConstellationPerson(id: 'h'),
            const ConstellationPerson(id: 'r'),
          ],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
            const ConstellationTrustEdgeEntity(src: 'b', dst: 'h', tier: 1),
          ],
          requests: [
            const ConstellationRequest(
              id: 'req-h',
              authorId: 'h',
              title: 'Attributed',
              status: 0,
            ),
            const ConstellationRequest(
              id: 'req-r',
              authorId: 'r',
              title: 'Ring only',
              status: 0,
            ),
          ],
        ),
      );
      cubit.droppedHolderIds = const {};
      cubit.emit(
        cubit.state.copyWith(
          capped: true,
          keptPeerIds: {...cubit.state.keptPeerIds}..remove('r'),
        ),
      );

      expect(cubit.droppedHolderIds, isEmpty);
      expect(
        cubit.absenceForPerson('r'),
        ConstellationNodeAbsence.ringBudgetOmitted,
      );
      expect(
        cubit.absenceForPerson('h'),
        isNot(ConstellationNodeAbsence.capDisplaced),
      );

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);
      expect(
        find.text('This ring connection is not drawn on the map'),
        findsOneWidget,
      );
      expect(
        find.text("Known connection omitted by the map's render budget"),
        findsNothing,
      );
    });

    testWidgets('all three field-level caps show distinguishable notices', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        _baseField(
          peersCapped: true,
          requestsCapped: true,
        ),
      );
      cubit.emit(cubit.state.copyWith(capped: true));

      await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

      expect(
        find.text('Some connection paths are not shown'),
        findsOneWidget,
      );
      expect(find.text('Some requests could not be loaded'), findsOneWidget);
      expect(
        find.text('Some people were omitted to keep the map readable'),
        findsOneWidget,
      );
    });

    testWidgets('overflow group expands labelled satellites', (tester) async {
      final requests = List.generate(
        5,
        (i) => ConstellationRequest(
          id: 'req-$i',
          authorId: 'a',
          title: 'Need $i',
          status: 0,
        ),
      );
      final cubit = await _loadCubit(
        _baseField(
          peers: [const ConstellationPerson(id: 'a')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: requests,
        ),
        viewport: const Size(400, 400),
      );

      await _pumpHarness(
        tester,
        cubit: cubit,
        width: 400,
        textScale: 1.0,
        extra: [
          ConstellationOverflowGroup(
            authorId: 'a',
            authorName: 'Author A',
            hiddenCount: 3,
          ),
        ],
      );

      final control = find.byKey(const Key('constellation.overflow.a'));
      expect(control, findsOneWidget);
      final size = tester.getSize(control);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));

      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(cubit.isSatelliteOverflowExpanded('a'), isTrue);
      expect(cubit.displayedRequestIds.length, 5);
    });

    testWidgets(
      'empty filtered result offers clear filters without despair copy',
      (
        tester,
      ) async {
        final cubit = await _loadCubit(
          _baseField(
            requests: [
              const ConstellationRequest(
                id: 'req-a',
                authorId: 'a',
                title: 'Tools',
                status: 0,
                needs: ['tools'],
              ),
            ],
          ),
        );
        cubit.setFilterCapabilitySlugs({'ride'});
        await _pumpHarness(tester, cubit: cubit, width: 900, textScale: 1.0);

        expect(find.text('No requests match these filters'), findsOneWidget);
        expect(find.text('Clear filters'), findsOneWidget);
        expect(find.textContaining('nobody'), findsNothing);
        expect(find.textContaining('no one needs'), findsNothing);

        await tester.tap(find.byKey(const Key('constellation.filter.clear')));
        await tester.pumpAndSettle();
        expect(cubit.hasActiveFilters, isFalse);
      },
    );

    test('filters use snapshot loadedAt not wall clock', () async {
      final loadedAt = DateTime.utc(2026, 1, 1, 12);
      final cubit = await _loadCubit(
        _baseField(
          requests: [
            ConstellationRequest(
              id: 'req-future',
              authorId: 'a',
              title: 'Soon',
              status: 0,
              startAt: loadedAt.add(const Duration(days: 3)),
            ),
          ],
        ).copyWith(loadedAt: loadedAt),
      );
      cubit.setFilterTiming(timingFilterWithinDays(7));
      final visible = cubit.discoverableRequestsForPerson('a');
      expect(visible.map((r) => r.id), ['req-future']);
    });
  });
}
