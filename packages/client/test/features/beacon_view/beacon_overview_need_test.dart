import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_need_brief.dart';
import 'package:tentura/features/beacon_view/ui/widget/overview/beacon_overview_tab.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

void main() {
  Beacon minimalBeacon({String? needSummary, String? description}) => Beacon(
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        id: 'b1',
        title: 'T',
        author: const Profile(id: 'u1', title: 'Author'),
        needSummary: needSummary,
        description: description ?? '',
      );

  BeaconViewState viewState(Beacon b) => BeaconViewState(beacon: b);

  Future<void> pumpApp(WidgetTester tester, Widget child) async {
    final profileCubit = _TestProfileCubit();
    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: profileCubit,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('BeaconOverviewTab legacy: one Need & context section + Coordination',
      (tester) async {
    final beacon = minimalBeacon(description: 'Only legacy body');
    await pumpApp(
      tester,
      BeaconOverviewTab(
        state: viewState(beacon),
        onViewAllCommitments: () {},
        onEditTimelineUpdate: (_) async {},
      ),
    );

    expect(find.text('Need & context'), findsOneWidget);
    expect(find.text('Coordination'), findsOneWidget);
    expect(find.text('Context & attachments'), findsNothing);
    // Legacy first card is non-collapsible; Coordination starts expanded → expand_less.
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });

  testWidgets(
      'BeaconOverviewTab need-first: Need (no chevron), Coordination, Context',
      (tester) async {
    final beacon = minimalBeacon(
      needSummary: 'Short canonical need statement for tests.',
      description: 'Longer context',
    );
    await pumpApp(
      tester,
      BeaconOverviewTab(
        state: viewState(beacon),
        onViewAllCommitments: () {},
        onEditTimelineUpdate: (_) async {},
      ),
    );

    expect(find.text('Need'), findsOneWidget);
    expect(find.text('Coordination'), findsOneWidget);
    expect(find.text('Context & attachments'), findsOneWidget);
    expect(find.text('Need & context'), findsNothing);
    expect(
      find.textContaining('Short canonical need'),
      findsOneWidget,
    );
    // Need + Context cards: one collapsed (expand_more), Coordination expanded (expand_less).
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
  });

  testWidgets('BeaconNeedBrief shows prefix when hasNeedSummary', (tester) async {
    final beacon = minimalBeacon(needSummary: 'Volunteers needed');
    await pumpApp(tester, BeaconNeedBrief(beacon: beacon));
    expect(find.textContaining('Need:'), findsOneWidget);
    expect(find.textContaining('Volunteers needed'), findsOneWidget);
  });

  testWidgets('BeaconNeedBrief empty when no needSummary', (tester) async {
    final beacon = minimalBeacon(description: 'x');
    await pumpApp(tester, BeaconNeedBrief(beacon: beacon));
    expect(find.byType(Text), findsNothing);
  });
}
