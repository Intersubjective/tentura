import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/forward/ui/widget/forward_bottom_composer.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_status_strip.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

class _GoldenProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  final sizes = <Size>[
    const Size(360, 800),
    const Size(600, 900),
    const Size(1024, 800),
  ];
  const scalers = <double>[1, 1.3];

  final inboxBeacon = Beacon(
    createdAt: DateTime.utc(2025, 4, 2),
    updatedAt: DateTime.utc(2025, 4, 18, 17, 6),
    id: 'b-inbox',
    title:
        'Inbox card typography: a deliberately long title that should wrap',
    context: 'General',
    author: const Profile(id: 'a1', title: 'Fionna Campbell'),
  );

  final myWorkBeacon = Beacon(
    createdAt: DateTime.utc(2025, 4, 2),
    updatedAt: DateTime.utc(2025, 4, 18, 12),
    id: 'b-mywork',
    title: 'My Work card: status strip and metadata line',
    context: 'Neighborhood',
    author: const Profile(id: 'a2', title: 'Alex River'),
  );

  final beaconViewBeacon = Beacon(
    createdAt: DateTime.utc(2025, 3, 2),
    updatedAt: DateTime.utc(2025, 4, 10),
    id: 'b-view',
    title: 'Beacon view header — compact title row',
    context: 'Projects',
    author: const Profile(id: 'a3', title: 'Jordan Lee'),
  );

  Future<void> pumpTypographyGolden(
    WidgetTester tester, {
    required String id,
    required Widget body,
    required Size logicalSize,
    required double textScaler,
  }) async {
    final profileCubit = _GoldenProfileCubit();
    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: profileCubit,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: logicalSize,
              textScaler: TextScaler.linear(textScaler),
            ),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    child: RepaintBoundary(
                      key: const Key('golden'),
                      child: SizedBox(
                        width: logicalSize.width,
                        child: body,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final safeScale = textScaler.toStringAsFixed(1).replaceAll('.', '_');
    final goldenName =
        'goldens/typography_${id}_${logicalSize.width.toInt()}x${logicalSize.height.toInt()}_s$safeScale.png';

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile(goldenName),
    );
  }

  group('typography overhaul goldens', () {
    testWidgets('inbox-style card', (tester) async {
      for (final s in sizes) {
        for (final scale in scalers) {
          await pumpTypographyGolden(
            tester,
            id: 'inbox',
            body: _InboxGoldenBody(beacon: inboxBeacon),
            logicalSize: s,
            textScaler: scale,
          );
        }
      }
    });

    testWidgets('my work-style card', (tester) async {
      for (final s in sizes) {
        for (final scale in scalers) {
          await pumpTypographyGolden(
            tester,
            id: 'my_work',
            body: _MyWorkGoldenBody(beacon: myWorkBeacon),
            logicalSize: s,
            textScaler: scale,
          );
        }
      }
    });

    testWidgets('beacon view header', (tester) async {
      for (final s in sizes) {
        for (final scale in scalers) {
          await pumpTypographyGolden(
            tester,
            id: 'beacon_header',
            body: _BeaconHeaderGoldenBody(beacon: beaconViewBeacon),
            logicalSize: s,
            textScaler: scale,
          );
        }
      }
    });

    testWidgets('forward composer', (tester) async {
      final controller = TextEditingController(
        text: 'Shared note to recipients',
      );
      addTearDown(controller.dispose);
      for (final s in sizes) {
        for (final scale in scalers) {
          await pumpTypographyGolden(
            tester,
            id: 'forward_composer',
            body: ForwardBottomComposer(
              selectedIds: const {'u1', 'u2'},
              noteExpanded: true,
              onToggleNoteExpanded: () {},
              sharedNoteController: controller,
              onSharedNoteChanged: (_) {},
              onForward: () {},
            ),
            logicalSize: s,
            textScaler: scale,
          );
        }
      }
    });

    testWidgets('bottom navigation bar', (tester) async {
      for (final s in sizes) {
        for (final scale in scalers) {
          await pumpTypographyGolden(
            tester,
            id: 'bottom_nav',
            body: const _BottomNavGoldenBody(),
            logicalSize: s,
            textScaler: scale,
          );
        }
      }
    });
  });
}

class _InboxGoldenBody extends StatelessWidget {
  const _InboxGoldenBody({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;
    return BeaconCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: beacon,
            menu: const SizedBox(width: 40, height: 40),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: beacon,
            updatedLine: 'Updated 2025-04-18 17:06',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              coordinationStatusLabel(l10n, beacon.coordinationStatus),
              style: theme.textTheme.labelSmall?.copyWith(
                color: coordinationStatusOnSurfaceColor(
                  scheme,
                  beacon.coordinationStatus,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MyWorkGoldenBody extends StatelessWidget {
  const _MyWorkGoldenBody({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    return BeaconCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: beacon,
            menu: const SizedBox(width: 40, height: 40),
          ),
          const SizedBox(height: 6),
          BeaconCardMetadataLine(
            beacon: beacon,
            updatedLine: 'Updated 2025-04-18 12:00',
          ),
          const SizedBox(height: 6),
          const MyWorkCardStatusStrip(
            data: MyWorkStatusLineData(
              slot1: 'Open',
              slot2: 'Closes 2025-05-01',
              slot3: '3 people committed',
              timeSlotOverdue: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _BeaconHeaderGoldenBody extends StatelessWidget {
  const _BeaconHeaderGoldenBody({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    return BeaconCardShell(
      child: BeaconCardHeaderRow(
        beacon: beacon,
        menu: const SizedBox(width: 40, height: 40),
      ),
    );
  }
}

class _BottomNavGoldenBody extends StatelessWidget {
  const _BottomNavGoldenBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final selectedIconFg = isDark
        ? scheme.onSecondaryContainer
        : scheme.onPrimary;
    final selectedLabelFg = scheme.onSurface;
    final unselectedFg = scheme.onSurfaceVariant;
    final indicator = isDark ? scheme.secondaryContainer : scheme.primary;

    return NavigationBarTheme(
      data: NavigationBarThemeData(
        height: context.tt.bottomNavHeight,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? selectedIconFg : unselectedFg,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          final base = TenturaText.navLabel(
            selected ? selectedLabelFg : unselectedFg,
          );
          return base.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      child: NavigationBar(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: indicator,
        selectedIndex: 1,
        onDestinationSelected: (_) {},
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            label: 'My work',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
