import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/semantics_free_tooltip.dart';

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

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(
        ConstellationField(
          loadedAt: DateTime.utc(2026, 9, 9),
          context: '',
          peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
          edges: const [
            ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1),
          ],
          requests: const [
            ConstellationRequest(
              id: 'req-a',
              authorId: 'a',
              title: 'Need tools',
              status: 0,
              needs: ['tools'],
            ),
          ],
        ),
      ),
      accountId: 'ego',
    ).store,
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

ConstellationComposerCubit _buildComposerCubit() => ConstellationComposerCubit(
  positions: const {},
  eligible: const {},
  createCubitFactory: (kind) => BeaconCreateCubit(kind: kind),
  forwardCubitFactory: (beaconId) =>
      ForwardCubit(beaconId: beaconId, embedded: true),
);

Future<void> _pumpAppBar(
  WidgetTester tester, {
  required ConstellationCubit cubit,
  required Size size,
  bool legendExpanded = false,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  ConstellationComposerCubit? composer,
  ConstellationSelectionCubit? selection,
  Widget? account,
}) async {
  await tester.binding.setSurfaceSize(size);
  Widget row = ConstellationAppBarRow(
    legendExpanded: legendExpanded,
    onToggleLegend: () {},
  );
  if (selection != null) {
    row = BlocProvider.value(value: selection, child: row);
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: TenturaResponsiveScope(
          child: BlocProvider.value(
            value: cubit,
            child: Builder(
              builder: (context) => Scaffold(
                appBar: TenturaTopBar.of(
                  context,
                  title: const SizedBox.shrink(),
                  row: composer == null
                      ? row
                      : BlocProvider.value(value: composer, child: row),
                  account: account,
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The pointer tooltips on the Map/List toggle's segments (#678: kept off
/// the segments themselves so they add no second name).
List<String> _segmentTooltips(WidgetTester tester) => tester
    .widgetList<SemanticsFreeTooltip>(
      find.descendant(
        of: find.byKey(const Key('constellation.app_bar.view_mode')),
        matching: find.byType(SemanticsFreeTooltip),
      ),
    )
    .map((tip) => tip.message)
    .toList();

void main() {
  testWidgets('composer hides legend, filters, view mode and create controls', (
    tester,
  ) async {
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpAppBar(tester, cubit: cubit, size: const Size(400, 800));
    cubit.enterComposing(
      draftCentre: Offset.zero,
      candidateIds: const {},
      selectedIds: const {},
      onToggle: (_) {},
    );
    await tester.pumpAndSettle();
    for (final key in [
      'legend',
      'filters',
      'view_mode',
      'create_here',
      'more',
    ]) {
      expect(find.byKey(Key('constellation.app_bar.$key')), findsNothing);
    }
    expect(
      find.byKey(const Key('constellation.app_bar.cancel_composer')),
      findsOneWidget,
    );
    cubit.exitComposing();
    await tester.pumpAndSettle();
    // On a phone the filters sit in the overflow menu (#659).
    expect(find.byKey(const Key('constellation.app_bar.more')), findsOneWidget);
  });
  group('ConstellationAppBarRow', () {
    testWidgets(
      'without a composer provided, the create button is absent',
      (tester) async {
        final cubit = await _loadCubit();
        await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));

        expect(
          find.byKey(const Key('constellation.app_bar.create_here')),
          findsNothing,
        );
        await cubit.close();
      },
    );

    testWidgets(
      'with a composer provided, the create button opens the kind menu',
      (tester) async {
        final cubit = await _loadCubit();
        final composer = _buildComposerCubit();
        await _pumpAppBar(
          tester,
          cubit: cubit,
          size: const Size(900, 800),
          composer: composer,
        );

        final createButton = find.byKey(
          const Key('constellation.app_bar.create_here'),
        );
        expect(createButton, findsOneWidget);

        await tester.tap(createButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('constellation.canvas.create_menu.post')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('constellation.canvas.create_menu.request')),
          findsOneWidget,
        );

        await cubit.close();
        await composer.close();
      },
    );

    testWidgets('filters button opens sheet with filter bar', (tester) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));

      await tester.tap(find.byKey(const Key('constellation.app_bar.filters')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('constellation.filter_bar')), findsOneWidget);
      await cubit.close();
    });

    testWidgets('legend stays slotted so view-mode toggle does not shift', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));

      final legend = find.byKey(const Key('constellation.app_bar.legend'));
      final toggle = find.byKey(const Key('constellation.app_bar.view_mode'));
      expect(legend, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isTrue,
      );
      final mapToggleOrigin = tester.getTopLeft(toggle);

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      expect(legend, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isFalse,
      );
      expect(tester.getTopLeft(toggle), mapToggleOrigin);

      cubit.setViewMode(ConstellationViewMode.map);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: legend, matching: find.byType(Visibility)),
            )
            .visible,
        isTrue,
      );
      expect(tester.getTopLeft(toggle), mapToggleOrigin);
      await cubit.close();
    });

    testWidgets('narrow width drops map/text labels but keeps icons', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(280, 800));

      expect(find.text('Map'), findsNothing);
      expect(find.text('List'), findsNothing);
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
      expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
      await cubit.close();
    });

    testWidgets('wide width keeps map/text labels', (tester) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));

      expect(find.text('Map'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      await cubit.close();
    });

    testWidgets('text scale 1.3 at wide width keeps map/text labels', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await _pumpAppBar(
        tester,
        cubit: cubit,
        size: const Size(900, 800),
        textScaler: TextScaler.linear(1.3),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      await cubit.close();
    });

    testWidgets(
      '375px width at text scale 1.0 and 1.3 has no layout exception',
      (
        tester,
      ) async {
        for (final locale in [const Locale('en'), const Locale('ru')]) {
          for (final scale in [1.0, 1.3]) {
            final cubit = await _loadCubit();
            await _pumpAppBar(
              tester,
              cubit: cubit,
              size: const Size(375, 800),
              textScaler: TextScaler.linear(scale),
              locale: locale,
            );
            expect(tester.takeException(), isNull);
            final tips = _segmentTooltips(tester);
            expect(tips, hasLength(2));
            for (final tip in tips) {
              expect(tip, isNotEmpty);
            }
            await cubit.close();
          }
        }
      },
    );

    testWidgets('text scale 2.0 has no overflow and segment tooltips remain', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      await tester.binding.setSurfaceSize(const Size(375, 800));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(375, 800),
              textScaler: TextScaler.linear(2.0),
            ),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: Builder(
                  builder: (context) => Scaffold(
                    appBar: TenturaTopBar.of(
                      context,
                      title: const SizedBox.shrink(),
                      row: ConstellationAppBarRow(
                        legendExpanded: false,
                        onToggleLegend: () {},
                      ),
                    ),
                    body: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final toggle = tester.widget<SegmentedButton<ConstellationViewMode>>(
        find.byKey(const Key('constellation.app_bar.view_mode')),
      );
      expect(toggle.segments.length, 2);
      expect(_segmentTooltips(tester), ['Map', 'List']);
      await cubit.close();
    });
  });
  // #659: on a 390 px phone the bar used to squeeze the title to "F…" and
  // the Map/List toggle to two 18x32 slivers.
  group('on a phone', () {
    const phone = Size(390, 844);
    final more = find.byKey(const Key('constellation.app_bar.more'));

    Future<(ConstellationCubit, ConstellationSelectionCubit)> pumpPhone(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      final composer = _buildComposerCubit();
      addTearDown(composer.close);
      final selection = ConstellationSelectionCubit();
      addTearDown(selection.close);
      await _pumpAppBar(
        tester,
        cubit: cubit,
        size: phone,
        locale: locale,
        textScaler: textScaler,
        composer: composer,
        selection: selection,
        // The profile avatar shares the bar on the real screen.
        account: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.account_circle),
        ),
      );
      return (cubit, selection);
    }

    for (final (locale, title) in [
      (const Locale('en'), 'Field'),
      (const Locale('ru'), 'Поле'),
    ]) {
      testWidgets('the title is not cut ($locale)', (tester) async {
        await pumpPhone(tester, locale: locale);
        expect(tester.takeException(), isNull);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(title),
        );
        final intrinsic = paragraph.getMaxIntrinsicWidth(double.infinity);
        expect(paragraph.size.width, greaterThanOrEqualTo(intrinsic - 0.5));
        // Shown whole and still readable: not shrunk to a speck either.
        expect(
          tester.getRect(find.text(title)).width,
          greaterThanOrEqualTo(0.75 * intrinsic),
        );
      });
    }

    // A larger system text size is the reader's choice: the title keeps it
    // (and ellipsizes) instead of being scaled back down to fit.
    testWidgets('at text scale 2.0 the title is not shrunk', (tester) async {
      await pumpPhone(tester, textScaler: TextScaler.linear(2));
      expect(tester.takeException(), isNull);
      final title = find.text('Field');
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(
        tester.getRect(title).height,
        closeTo(paragraph.size.height, 0.5),
      );
    });

    testWidgets('both Map/List segments are full 48 dp targets', (
      tester,
    ) async {
      await pumpPhone(tester);
      final segments = find.descendant(
        of: find.byKey(const Key('constellation.app_bar.view_mode')),
        matching: find.byType(TextButton),
      );
      expect(segments, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final size = tester.getSize(segments.at(i));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
      expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    });

    testWidgets('legend, select, create and filters move into a menu', (
      tester,
    ) async {
      await pumpPhone(tester);
      for (final key in ['legend', 'select', 'create_here', 'filters']) {
        expect(find.byKey(Key('constellation.app_bar.$key')), findsNothing);
      }
      expect(find.byKey(const Key('constellation.app_bar.search')), findsOne);

      await tester.tap(more);
      await tester.pumpAndSettle();
      for (final key in ['legend', 'select', 'createHere', 'filters']) {
        expect(
          find.byKey(Key('constellation.app_bar.more.$key')),
          findsOneWidget,
        );
      }
    });

    testWidgets('the menu items act', (tester) async {
      final (_, selection) = await pumpPhone(tester);

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('constellation.app_bar.more.select')),
      );
      await tester.pumpAndSettle();
      expect(selection.state.selecting, isTrue);

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('constellation.app_bar.more.createHere')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.canvas.create_menu.request')),
        findsOneWidget,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('constellation.app_bar.more.filters')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('constellation.filter_bar')), findsOneWidget);
    });

    testWidgets('the list view menu holds no map-only items', (tester) async {
      final (cubit, _) = await pumpPhone(tester);
      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();

      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.app_bar.more.legend')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('constellation.app_bar.more.select')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('constellation.app_bar.more.filters')),
        findsOneWidget,
      );
    });

    testWidgets('a wide window keeps the inline buttons', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));
      expect(more, findsNothing);
      expect(find.byKey(const Key('constellation.app_bar.filters')), findsOne);
      expect(find.byKey(const Key('constellation.app_bar.legend')), findsOne);
    });
  });

  // #678: a labelled segment was read as "Map Map".
  testWidgets('a labelled segment names itself once', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = await _loadCubit();
    addTearDown(cubit.close);
    await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));
    expect(find.text('Map'), findsOneWidget);

    final data = tester
        .getSemantics(
          find.ancestor(
            of: find.text('Map'),
            matching: find.byType(TextButton),
          ),
        )
        .getSemanticsData();
    final spoken = '${data.label}\n${data.tooltip}';
    expect(RegExp('Map').allMatches(spoken), hasLength(1));
    semantics.dispose();
  });

  // #678 (QA on 7.50.7): the view toggle was still read "Map Map" and, when
  // selected, "List List": the tooltip added a second name beside the label.
  group('the view toggle names each segment once', () {
    List<SemanticsData> namedNodes(WidgetTester tester, String name) {
      final found = <SemanticsData>[];
      bool visit(SemanticsNode node) {
        // A node merged into its button is read as part of the button.
        if (node.isMergedIntoParent) return true;
        final data = node.getSemanticsData();
        if (data.label.contains(name) ||
            data.tooltip.contains(name) ||
            data.value.contains(name) ||
            data.hint.contains(name)) {
          found.add(data);
        }
        node.visitChildren(visit);
        return true;
      }

      visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      return found;
    }

    for (final (mode, size) in [
      (ConstellationViewMode.map, const Size(900, 800)),
      (ConstellationViewMode.text, const Size(900, 800)),
      (ConstellationViewMode.map, const Size(400, 800)),
    ]) {
      testWidgets('in ${mode.name} view at ${size.width.toInt()} wide', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        cubit.setViewMode(mode);
        await _pumpAppBar(tester, cubit: cubit, size: size);

        for (final name in ['Map', 'List']) {
          final nodes = namedNodes(tester, name);
          expect(nodes, hasLength(1), reason: '$name is one node');
          expect(nodes.single.label, name, reason: '$name is its label');
          expect(nodes.single.tooltip, isEmpty, reason: '$name, no tooltip');
        }
        semantics.dispose();
      });
    }

    // #678 (QA on 7.54.0): hovering a toolbar button put its tooltip into
    // the tree beside it, and the web read the button as "Map Map", "List
    // List" or "Show legend Show legend" while (and after) it showed.
    for (final (mode, name) in [
      (ConstellationViewMode.map, 'Map'),
      (ConstellationViewMode.map, 'List'),
      (ConstellationViewMode.text, 'List'),
      (ConstellationViewMode.map, 'Show legend'),
      (ConstellationViewMode.map, 'Filters'),
    ]) {
      testWidgets('while hovered, $name in ${mode.name} view', (tester) async {
        final semantics = tester.ensureSemantics();
        final cubit = await _loadCubit();
        addTearDown(cubit.close);
        cubit.setViewMode(mode);
        await _pumpAppBar(tester, cubit: cubit, size: const Size(900, 800));
        final shownBefore = find.text(name).evaluate().length;

        final button = switch (name) {
          'Map' => find.byIcon(TenturaIcons.graph),
          'List' => find.byIcon(Icons.view_list_outlined),
          'Show legend' => find.byKey(
            const Key('constellation.app_bar.legend'),
          ),
          _ => find.byKey(const Key('constellation.app_bar.filters')),
        };
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(button));
        await tester.pumpAndSettle();

        // The tooltip shows for the pointer…
        expect(find.text(name), findsNWidgets(shownBefore + 1));
        // …and the name is still read once, from the button alone.
        final nodes = namedNodes(tester, name);
        expect(nodes, hasLength(1), reason: '$name is one node');
        expect(nodes.single.label, name);
        expect(nodes.single.tooltip, isEmpty);
        expect(nodes.single.flagsCollection.isButton, isTrue);

        await mouse.moveTo(const Offset(1, 799));
        await tester.pumpAndSettle();
        semantics.dispose();
      });
    }

    testWidgets('in Russian', (tester) async {
      final semantics = tester.ensureSemantics();
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpAppBar(
        tester,
        cubit: cubit,
        size: const Size(900, 800),
        locale: const Locale('ru'),
      );

      for (final name in ['Карта', 'Список']) {
        final nodes = namedNodes(tester, name);
        expect(nodes, hasLength(1), reason: '$name is one node');
        expect(nodes.single.label, name);
        expect(nodes.single.tooltip, isEmpty);
      }
      semantics.dispose();
    });
  });

  // #659: on a phone the degree chips ran off the edge with no hint.
  group('the chip row', () {
    Future<void> pumpChips(WidgetTester tester, Size size) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: TenturaResponsiveScope(
              child: BlocProvider.value(
                value: cubit,
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: ConstellationVisibilityBar(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final fadeStart = find.byKey(const Key('constellation.show.fade_start'));
    final fadeEnd = find.byKey(const Key('constellation.show.fade_end'));
    final lastChip = find.byKey(const Key('constellation.show.degree.further'));

    testWidgets('fades where chips are hidden and scrolls to the last one', (
      tester,
    ) async {
      await pumpChips(tester, const Size(390, 844));
      expect(fadeEnd, findsOneWidget);
      expect(fadeStart, findsNothing);
      expect(tester.getRect(lastChip).right, greaterThan(390));

      await tester.drag(
        find.byKey(const Key('constellation.show')),
        const Offset(-1000, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(lastChip).right, lessThanOrEqualTo(390));
      expect(fadeEnd, findsNothing);
      expect(fadeStart, findsOneWidget);
    });

    testWidgets('has no fade when every chip fits', (tester) async {
      await pumpChips(tester, const Size(1400, 900));
      expect(tester.getRect(lastChip).right, lessThanOrEqualTo(1400));
      expect(fadeEnd, findsNothing);
      expect(fadeStart, findsNothing);
    });
  });
}
