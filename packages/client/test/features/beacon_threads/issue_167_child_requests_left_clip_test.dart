import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_operational_header_card.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconViewCubit extends Cubit<BeaconViewState> implements BeaconViewCubit {
  _FakeBeaconViewCubit(BeaconViewState initial) : super(initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconViewState _authorBeaconState() {
  final now = DateTime.utc(2026, 1, 1);
  const author = Profile(id: 'auth', displayName: 'Author');
  return BeaconViewState(
    beacon: Beacon(
      id: 'parent-1',
      title: 'Parent request',
      author: author,
      createdAt: now,
      updatedAt: now,
      status: BeaconStatus.open,
    ),
    myProfile: author,
    roomParticipantsLoaded: true,
  );
}

Widget _wrapRuNowSurface({
  required BeaconHierarchyCubit hierarchyCubit,
  required BeaconViewCubit beaconViewCubit,
  required ScreenCubit screenCubit,
  double? panelWidth,
}) {
  final surface = BeaconNowSurface(
    beaconViewCubit: beaconViewCubit,
    screenCubit: screenCubit,
    beaconState: beaconViewCubit.state,
    onSurfaceSelected: (_) {},
    onActivatePeopleTabAttention: () {},
    onFocusCoordinationItem: (_) {},
    onOpenGeneralThread: () {},
  );
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: TenturaResponsiveScope(
      child: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<BeaconHierarchyCubit>.value(value: hierarchyCubit),
            BlocProvider<BeaconViewCubit>.value(value: beaconViewCubit),
          ],
          child: panelWidth == null
              ? surface
              // The Now panel beside the chat on a wide window.
              : Align(
                  alignment: AlignmentDirectional.topStart,
                  child: SizedBox(width: panelWidth, child: surface),
                ),
        ),
      ),
    ),
  );
}

double _leftInsetFromAncestor({
  required WidgetTester tester,
  required Finder textFinder,
  required Finder ancestorFinder,
}) {
  final textBox = tester.renderObject<RenderBox>(textFinder);
  final ancestorBox = tester.renderObject<RenderBox>(ancestorFinder);
  final globalLeft = textBox.localToGlobal(Offset.zero).dx;
  final ancestorGlobalLeft = ancestorBox.localToGlobal(Offset.zero).dx;
  return globalLeft - ancestorGlobalLeft;
}

void _expectNoHorizontalClipOnText({
  required WidgetTester tester,
  required Finder textFinder,
  required double minLeftInset,
  required String label,
}) {
  final textBox = tester.renderObject<RenderBox>(textFinder);
  final size = textBox.size;
  expect(size.width, greaterThan(0), reason: '$label should layout with width');

  final paintBounds = textBox.paintBounds;
  expect(
    paintBounds.left,
    greaterThanOrEqualTo(-0.01),
    reason: '$label paint extends past its own left edge (horizontal clip)',
  );

  final overflow = tester.takeException();
  expect(overflow, isNull, reason: '$label layout should not throw overflow');

  final scrollView = find.byType(CustomScrollView);
  final insetInScrollView = _leftInsetFromAncestor(
    tester: tester,
    textFinder: textFinder,
    ancestorFinder: scrollView,
  );
  expect(
    insetInScrollView,
    greaterThanOrEqualTo(minLeftInset),
    reason:
        '$label must sit at least screenHPadding inside the NOW scroll viewport '
        '(issue #167 — flush-left copy reads as clipped vs header)',
  );
}

void main() {
  testWidgets(
    'issue #167 ru child-requests title and empty copy are inset in NOW viewport',
    (tester) async {
      const viewport = Size(375, 812);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final hierarchyCubit = BeaconHierarchyCubit(
        beaconId: 'parent-1',
        hierarchyCase: buildBeaconHierarchyCaseForTest(
          FakeBeaconHierarchyRepositoryPort(),
          createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
          beacons: _NoopBeaconWritePort(),
          commandStore: InMemoryBeaconChildCommandStore(),
        ),
      );
      addTearDown(hierarchyCubit.close);

      final beaconViewCubit = _FakeBeaconViewCubit(_authorBeaconState());
      addTearDown(beaconViewCubit.close);

      final screenCubit = ScreenCubit.local();
      addTearDown(screenCubit.close);

      await tester.pumpWidget(
        _wrapRuNowSurface(
          hierarchyCubit: hierarchyCubit,
          beaconViewCubit: beaconViewCubit,
          screenCubit: screenCubit,
        ),
      );
      await hierarchyCubit.load();
      await tester.pumpAndSettle();

      final l10n = await L10n.delegate.load(const Locale('ru'));
      final titleFinder = find.text(l10n.beaconChildRequestsTitle);
      final emptyFinder = find.text(l10n.beaconChildRequestsEmpty);

      expect(titleFinder, findsOneWidget);
      expect(emptyFinder, findsOneWidget);
      expect(find.byType(BeaconChildRequestsSection), findsOneWidget);
      expect(find.byType(BeaconOperationalHeaderCard), findsOneWidget);

      final tt = tester.element(find.byType(BeaconChildRequestsSection)).tt;
      final minInset = tt.screenHPadding;

      _expectNoHorizontalClipOnText(
        tester: tester,
        textFinder: titleFinder,
        minLeftInset: minInset,
        label: 'beaconChildRequestsTitle',
      );
      _expectNoHorizontalClipOnText(
        tester: tester,
        textFinder: emptyFinder,
        minLeftInset: minInset,
        label: 'beaconChildRequestsEmpty',
      );

      // The section sits on the screen column edge shared by the other Now
      // sections (not on the HUD rows' text line).
      final headerInset = tester
          .element(find.byType(CustomScrollView))
          .tt
          .screenHPadding;
      final titleInset = _leftInsetFromAncestor(
        tester: tester,
        textFinder: titleFinder,
        ancestorFinder: find.byType(CustomScrollView),
      );
      expect(
        titleInset,
        closeTo(headerInset, 1),
        reason:
            'child-requests header should sit on the screen column edge',
      );
    },
  );

  // #465: in the Now panel of a wide window the RU "Create child request"
  // button got half the header row and was cut to «Создать дочерний …».
  testWidgets('ru create-child button label fits in the wide Now panel', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final hierarchyCubit = BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: buildBeaconHierarchyCaseForTest(
        FakeBeaconHierarchyRepositoryPort(),
        createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
        beacons: _NoopBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
    addTearDown(hierarchyCubit.close);
    final beaconViewCubit = _FakeBeaconViewCubit(_authorBeaconState());
    addTearDown(beaconViewCubit.close);
    final screenCubit = ScreenCubit.local();
    addTearDown(screenCubit.close);

    await tester.pumpWidget(
      _wrapRuNowSurface(
        hierarchyCubit: hierarchyCubit,
        beaconViewCubit: beaconViewCubit,
        screenCubit: screenCubit,
        panelWidth: 400,
      ),
    );
    await hierarchyCubit.load();
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('ru'));
    final label = tester.renderObject<RenderParagraph>(
      find.text(l10n.beaconCreateChildRequest),
    );
    expect(label.didExceedMaxLines, isFalse);
    expect(
      tester.renderObject<RenderParagraph>(
        find.text(l10n.beaconChildRequestsTitle),
      ).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
