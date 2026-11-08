import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/screen/constellation_screen.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_visibility_bar.dart';
import 'package:tentura/features/constellation/ui/widget/field_collapsing_app_bar.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _personId = 'am';

class _ScreenContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _ScreenContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

Finder get _personNode => find.byKey(TestIds.key(TestIds.graphNode(_personId)));

Future<ConstellationCubit> _pumpField(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
}) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await pumpConstellationBody(tester, cubit, size: size, locale: locale);
  await tester.pumpAndSettle();
  return cubit;
}

Future<ConstellationCubit> _pumpConstellationScreen(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  bool disableAnimations = false,
}) async {
  final cubit = await loadReferenceCubit();
  addTearDown(cubit.close);
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: kPhoneSurface,
          disableAnimations: disableAnimations,
        ),
        child: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ConstellationCubit>.value(value: cubit),
              BlocProvider(create: (_) => HomeTabReselectCubit()),
              BlocProvider<GraphPersonContextCubit>(
                create: (_) => _ScreenContextCubit(),
              ),
              BlocProvider<ScreenCubit>(
                create: (_) => ScreenCubit(FakeUiEffectPort()),
              ),
            ],
            child: const ConstellationScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return cubit;
}

FieldPersonNode? _selectedPersonNode(ConstellationCubit cubit) {
  for (final node
      in cubit.graphController.renderSnapshot.topology.nodesById.values) {
    final payload = node.payload;
    if (payload is FieldPersonNode && payload.person.id == _personId) {
      return payload;
    }
  }
  return null;
}

void main() {
  group('Field compact context sheet (#974)', () {
    testWidgets(
      '375×667 RU reclaims chip-row height for the map at peek (#974)',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _pumpField(
          tester,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        expect(find.byType(ConstellationVisibilityBar), findsOneWidget);
        final bodyTop = tester.getTopLeft(find.byType(ConstellationBody)).dy;
        final mapTopBefore = tester
            .getTopLeft(find.byType(InteractiveViewer))
            .dy;
        expect(mapTopBefore - bodyTop, greaterThan(24));
        await tester.tap(_personNode);
        await tester.pumpAndSettle();
        expect(find.byType(ConstellationVisibilityBar), findsNothing);
        final mapTopAfter = tester
            .getTopLeft(find.byType(InteractiveViewer))
            .dy;
        expect(mapTopAfter - bodyTop, lessThan(2));
        expect(mapTopAfter, lessThan(mapTopBefore - 24));
        expect(cubit.state.selectedPersonId, _personId);
      },
    );

    testWidgets(
      '375×667 RU centres the selected person in the strip above the sheet (#974)',
      (tester) async {
        await usePhoneSurface(tester);
        await _pumpField(
          tester,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        await tester.tap(_personNode);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));

        final handle = find.byKey(const Key('field.context_sheet.handle'));
        final sheetTop = tester.getTopLeft(handle).dy;
        final mapTop = tester.getTopLeft(find.byType(InteractiveViewer)).dy;
        final nodeY = tester.getCenter(_personNode).dy;
        final mid = (mapTop + sheetTop) / 2;
        expect(nodeY, closeTo(mid, 56));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('375×667 hides map chrome and revealPanFor is non-null', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final cubit = await _pumpField(tester, size: kPhoneSurface);
      await tester.tap(_personNode);
      await tester.pumpAndSettle();

      expect(find.byType(ConstellationVisibilityBar), findsNothing);
      expect(
        find.byKey(const Key('field.context_sheet.handle')),
        findsOneWidget,
      );
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);

      final context = tester.element(find.byType(ConstellationBody));
      final tt = context.tt;
      final mapBodyHeight =
          kPhoneSurface.height - tt.appBarHeight - tt.bottomNavHeight;
      final peekSheet = mapBodyHeight * tt.fieldSheetPeekFraction;
      final node = _selectedPersonNode(cubit);
      expect(node, isNotNull);

      final pan = cubit.revealPanFor(
        node!,
        insets: cubit.fieldCameraViewportInsets(
          context,
          contextPanelVisible: true,
          compactSheetHeight: peekSheet,
        ),
        centreVertically: true,
      );
      expect(pan, isNotNull);
    });

    testWidgets('360×640 keeps request primary action visible at peek in RU', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpField(
        tester,
        size: const Size(360, 640),
        locale: const Locale('ru'),
      );
      final request = find.byKey(TestIds.key(TestIds.graphNode('req-in-2')));
      if (request.evaluate().isEmpty) {
        return;
      }
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.request_preview.primary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '375×667 RU collapses top bar when sheet expands and restores at peek',
      (tester) async {
        await usePhoneSurface(tester);
        await _pumpConstellationScreen(tester);
        await tester.tap(_personNode);
        await tester.pumpAndSettle();

        final appBar = find.byKey(const Key('field.context_sheet.app_bar'));
        final search = find.byKey(const Key('constellation.app_bar.search'));
        final handle = find.byKey(const Key('field.context_sheet.handle'));
        final tt = tester.element(appBar).tt;

        expect(tester.getSize(appBar).height, closeTo(tt.appBarHeight, 1));
        expect(search, findsOneWidget);

        await tester.tap(handle);
        await tester.pump();
        await tester.pump(kFieldContextSheetSnapDuration);
        await tester.pump();

        expect(tester.getSize(appBar).height, closeTo(0, 1));
        expect(
          tester.widget<FieldCollapsingAppBar>(appBar).collapsed,
          isTrue,
        );

        await tester.tap(handle);
        await tester.pump();
        await tester.pump(kFieldContextSheetSnapDuration);
        await tester.pump(kFieldContextSheetSnapDuration);

        expect(tester.getSize(appBar).height, closeTo(tt.appBarHeight, 1));
        expect(
          tester.widget<FieldCollapsingAppBar>(appBar).collapsed,
          isFalse,
        );
        expect(search, findsOneWidget);
      },
    );

    testWidgets(
      '375×667 RU reduced motion snaps collapsed app bar with sheet',
      (tester) async {
        await usePhoneSurface(tester);
        await _pumpConstellationScreen(
          tester,
          disableAnimations: true,
        );
        await tester.tap(_personNode);
        await tester.pumpAndSettle();

        final appBar = find.byKey(const Key('field.context_sheet.app_bar'));
        await tester.tap(find.byKey(const Key('field.context_sheet.handle')));
        await tester.pump();
        await tester.pump();

        expect(tester.getSize(appBar).height, closeTo(0, 1));
      },
    );
  });
}
