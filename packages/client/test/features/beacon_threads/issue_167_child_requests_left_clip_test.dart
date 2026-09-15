import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
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
}) {
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
          child: BeaconNowSurface(
            beaconViewCubit: beaconViewCubit,
            screenCubit: screenCubit,
            beaconState: beaconViewCubit.state,
            onSurfaceSelected: (_) {},
            onActivatePeopleTabAttention: () {},
            onFocusCoordinationItem: (_) {},
            onOpenGeneralThread: () {},
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

      final headerInset = _leftInsetFromAncestor(
        tester: tester,
        textFinder: find.descendant(
          of: find.byType(BeaconOperationalHeaderCard),
          matching: find.byType(Text),
        ).first,
        ancestorFinder: find.byType(CustomScrollView),
      );
      final titleInset = _leftInsetFromAncestor(
        tester: tester,
        textFinder: titleFinder,
        ancestorFinder: find.byType(CustomScrollView),
      );
      expect(
        titleInset,
        closeTo(headerInset, 1),
        reason:
            'child-requests header should align with operational header content',
      );
    },
  );
}
