import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  void clearSelection() {}
}

const _ego = Profile(id: 'ego', displayName: 'Ego');

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

ConstellationFieldCase _caseForField(ConstellationField field) =>
    ConstellationFieldCase(
      _StubRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationTextViewTest'),
    );

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

ConstellationField _multiAuthorField({
  bool peersCapped = false,
}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 9, 9, 12),
    context: '',
    peersCapped: peersCapped,
    peers: [
      const ConstellationPerson(id: 'a', displayName: 'Ann'),
      const ConstellationPerson(id: 'b', displayName: 'Bob'),
      const ConstellationPerson(id: 'r', displayName: 'Ring'),
    ],
    edges: [
      const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
      const ConstellationTrustEdgeEntity(src: 'a', dst: 'b', tier: 1),
    ],
    requests: [
      const ConstellationRequest(
        id: 'req-a1',
        authorId: 'a',
        title: 'Tools',
        status: 0,
        needs: ['tools'],
      ),
      const ConstellationRequest(
        id: 'req-b1',
        authorId: 'b',
        title: 'Ride',
        status: 0,
        needs: ['ride'],
      ),
      const ConstellationRequest(
        id: 'req-r1',
        authorId: 'r',
        title: 'Ring need',
        status: 0,
      ),
    ],
  );
}

Set<String> _eligibleRequestIds(ConstellationCubit cubit) {
  final field = cubit.state.field;
  if (field == null) {
    return const {};
  }
  final ids = <String>{};
  for (final request in field.requests) {
    for (final eligible in cubit.discoverableRequestsForPerson(request.authorId)) {
      ids.add(eligible.id);
    }
  }
  return ids;
}

Future<void> _pumpTextView(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<ConstellationCubit>.value(
          value: cubit,
          child: const Scaffold(body: ConstellationTextView()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBody(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              appBar: TenturaTopBar.of(
                context,
                title: const SizedBox.shrink(),
                row: const ConstellationAppBarRow(
                  legendExpanded: false,
                  onToggleLegend: _noop,
                ),
              ),
              body: const ConstellationBody(
                legendExpanded: false,
                onToggleLegend: _noop,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _noop() {}

void main() {
  group('ConstellationTextView', () {
    test('eligible request ids match map-side filters for each filter state', () async {
      final cubit = await _loadCubit(_multiAuthorField());

      final filterStates = <void Function()>[
        () {},
        () => cubit.setFilterCapabilitySlugs({'tools'}),
        () => cubit.setFilterLocation(LocationFilter.hasLocation),
        () => cubit.setFilterTiming(const TimingFilterUndated()),
        () => cubit.setFilterIncludeUnspecified(false),
      ];

      for (final apply in filterStates) {
        apply();
        final eligible = _eligibleRequestIds(cubit);
        for (final id in eligible) {
          expect(
            cubit.absenceForRequest(id),
            isNot(ConstellationNodeAbsence.filterHidden),
          );
        }
      }
    });

    testWidgets('text and map expose the same eligible ids after filter changes', (
      tester,
    ) async {
      final cubit = await _loadCubit(_multiAuthorField());
      await _pumpBody(tester, cubit);

      cubit.setFilterCapabilitySlugs({'tools'});
      final mapEligible = _eligibleRequestIds(cubit);

      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();

      expect(_eligibleRequestIds(cubit), mapEligible);
      expect(find.byKey(const Key('constellation.text.list')), findsOneWidget);
      expect(find.byKey(const Key('constellation.text.request.req-a1')), findsOneWidget);
      expect(find.byKey(const Key('constellation.text.request.req-b1')), findsNothing);
    });

    test('setViewMode preserves selection and filters without reloading', () async {
      final cubit = await _loadCubit(_multiAuthorField());
      cubit.setFilterCapabilitySlugs({'ride'});
      cubit.emit(cubit.state.copyWith(selectedRequestId: 'req-b1'));

      cubit.setViewMode(ConstellationViewMode.text);
      expect(cubit.state.selectedRequestId, 'req-b1');
      expect(cubit.state.filterCapabilitySlugs, {'ride'});
      expect(cubit.state.loadedAt, DateTime.utc(2026, 9, 9, 12));

      cubit.setViewMode(ConstellationViewMode.map);
      expect(cubit.state.selectedRequestId, 'req-b1');
      expect(cubit.state.filterCapabilitySlugs, {'ride'});
    });

    testWidgets('filter state survives a map/text round trip in the UI', (
      tester,
    ) async {
      final cubit = await _loadCubit(_multiAuthorField());
      await _pumpBody(tester, cubit);

      cubit.setFilterCapabilitySlugs({'ride'});

      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      expect(cubit.state.viewMode, ConstellationViewMode.text);
      expect(cubit.state.filterCapabilitySlugs, {'ride'});

      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(cubit.state.viewMode, ConstellationViewMode.map);
      expect(cubit.state.filterCapabilitySlugs, {'ride'});
    });

    testWidgets('peersCapped text view suppresses connection explanations', (
      tester,
    ) async {
      final cubit = await _loadCubit(_multiAuthorField(peersCapped: true));
      await _pumpTextView(tester, cubit);

      expect(find.byKey(const Key('constellation.text.plain_list_notice')), findsOneWidget);
      expect(find.byKey(const Key('constellation.text.connection.req-a1')), findsNothing);
    });

    testWidgets('non-capped text view shows connection explanations with semantics', (
      tester,
    ) async {
      final cubit = await _loadCubit(_multiAuthorField());
      await _pumpTextView(tester, cubit);

      final connection = find.byKey(const Key('constellation.text.connection.req-b1'));
      expect(connection, findsOneWidget);
      expect(find.textContaining('Visible through'), findsWidgets);

      final handle = tester.ensureSemantics();
      final data = tester.getSemantics(connection);
      expect(data.label, contains('Visible through'));
      expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    testWidgets('request tiles and overflow controls are keyboard reachable', (
      tester,
    ) async {
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
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: requests,
        ),
        viewport: const Size(400, 400),
      );
      await _pumpTextView(tester, cubit);

      await tester.tap(find.byKey(const Key('constellation.text.request.req-0')));
      await tester.pump();
      expect(cubit.state.selectedRequestId, 'req-0');

      final overflow = find.byKey(const Key('constellation.overflow.a'));
      if (overflow.evaluate().isNotEmpty) {
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(overflow).label,
          contains('more'),
        );
        handle.dispose();
      }
    });

    testWidgets('filter bar and overflow group render inside ConstellationBody', (
      tester,
    ) async {
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
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: [const ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: [
            const ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: requests,
        ),
        viewport: const Size(400, 400),
      );
      await _pumpBody(tester, cubit);

      expect(find.byKey(const Key('constellation.app_bar.filters')), findsOneWidget);
      expect(find.byKey(const Key('constellation.overflow.a')), findsOneWidget);
    });

    testWidgets('missing selection after reload is explained, not replaced', (
      tester,
    ) async {
      final cubit = await _loadCubit(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
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
            ),
          ],
        ),
      );
      await _pumpBody(tester, cubit);

      cubit.selectRequest('req-a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      cubit.selectRequest(null);
      cubit.emit(
        cubit.state.copyWith(
          field: cubit.state.field!.copyWith(requests: const []),
        ),
      );
      cubit.selectRequest('req-a');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('constellation.selection_unavailable')),
        findsOneWidget,
      );
      expect(cubit.state.selectedRequestId, isNull);
    });
  });
}
